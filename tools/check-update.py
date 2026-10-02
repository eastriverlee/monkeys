#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

repository = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1]).resolve()
installer = repository / "plugins/monkeys/skills/monkeys/scripts/install.sh"


def write_executable(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    path.chmod(0o755)


def prepare_downloads(directory):
    downloads = directory / "downloads"
    downloads.mkdir()
    shutil.copyfile(installer, downloads / "install")
    replacement = downloads / "monkeys"
    write_executable(replacement, "#!/bin/sh\necho updated-fixture\n")
    archive = downloads / "monkeys-macos-universal.tar.gz"
    if sys.platform != "darwin":
        machine = os.uname().machine
        architecture = "arm64" if machine in {"aarch64", "arm64"} else "x86_64"
        archive = downloads / f"monkeys-linux-{architecture}.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        bundle.add(replacement, arcname="monkeys")
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (downloads / "checksums.txt").write_text(f"{checksum}  {archive.name}\n")
    return downloads


def prepare_environment(directory, downloads):
    commands = directory / "commands"
    write_executable(commands / "curl", f"""#!{sys.executable}
import os
from pathlib import Path
import shutil
import sys
arguments = sys.argv[1:]
destination = arguments[arguments.index('-o') + 1]
url = next(argument for argument in arguments if argument.startswith('https://'))
source = Path(os.environ['UPDATE_DOWNLOADS'], url.rsplit('/', 1)[1])
if '/v0.0.0/' in url or not source.is_file():
    sys.exit(22)
shutil.copyfile(source, destination)
""")
    return dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                UPDATE_DOWNLOADS=str(downloads), INSTALL_DIRECTORY=str(directory / "wrong"),
                MONKEYS_VERSION="v0.0.0")


def run_update(executable, command, environment):
    return subprocess.run([str(executable), command], env=environment, capture_output=True, text=True)


def check_direct_update(command, failure):
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        downloads = prepare_downloads(directory)
        environment = prepare_environment(directory, downloads)
        executable = directory / "custom bin" / "monkeys"
        executable.parent.mkdir()
        shutil.copy2(binary, executable)
        if failure == "missing":
            (downloads / "checksums.txt").unlink()
        if failure == "mismatch":
            (downloads / "checksums.txt").write_text("0" * 64 + "  " + next(downloads.glob("*.tar.gz")).name + "\n")
        result = run_update(executable, command, environment)
        assert (result.returncode == 0) == (failure is None), result.stderr
        expected = (downloads / "monkeys").read_bytes() if failure is None else binary.read_bytes()
        assert executable.read_bytes() == expected, result.stderr
        assert not (directory / "wrong").exists()
        assert not list(executable.parent.glob(".monkeys.*"))


def check_homebrew_update(command):
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        executable = directory / "Cellar/monkeys/1.5.0/bin/monkeys"
        executable.parent.mkdir(parents=True)
        shutil.copy2(binary, executable)
        captured = directory / "arguments"
        write_executable(directory / "bin/brew", f"#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$UPDATE_ARGUMENTS\"\n")
        environment = dict(os.environ, UPDATE_ARGUMENTS=str(captured))
        result = run_update(executable, command, environment)
        assert result.returncode == 0, result.stderr
        assert captured.read_text() == "upgrade\neastriverlee/tap/monkeys\n"
        assert executable.read_bytes() == binary.read_bytes()


for command in ["update", "upgrade"]:
    for failure in [None, "missing", "mismatch"]:
        check_direct_update(command, failure)
    check_homebrew_update(command)
print("update and upgrade passed: direct install, Homebrew, checksum failures")
