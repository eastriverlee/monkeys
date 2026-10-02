#!/bin/sh
# Fetch the monkeys binary for this machine from the latest GitHub release.
#
#   sh tools/install.sh                     into ~/.local/bin
#   INSTALL_DIRECTORY=/usr/local/bin sh tools/install.sh
#   MONKEYS_VERSION=v1.2.0 sh tools/install.sh
set -eu

REPOSITORY="eastriverlee/monkeys"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY:-$HOME/.local/bin}"

asset_name() {
    system=$(uname -s)
    machine=$(uname -m)
    case "$system" in
        Darwin) echo "monkeys-macos-universal.tar.gz" ;;
        Linux)
            case "$machine" in
                x86_64) echo "monkeys-linux-x86_64.tar.gz" ;;
                aarch64 | arm64) echo "monkeys-linux-arm64.tar.gz" ;;
                *) echo "no monkeys build for Linux $machine" >&2; exit 1 ;;
            esac
            ;;
        *) echo "no monkeys build for $system" >&2; exit 1 ;;
    esac
}

release_url() {
    if [ -n "${MONKEYS_VERSION:-}" ]; then
        echo "https://github.com/$REPOSITORY/releases/download/$MONKEYS_VERSION"
    else
        echo "https://github.com/$REPOSITORY/releases/latest/download"
    fi
}

asset=$(asset_name)
base=$(release_url)
work=$(mktemp -d)
replacement=""
trap 'rm -rf "$work"; if [ -n "$replacement" ]; then rm -f "$replacement"; fi' EXIT

echo "downloading $asset"
curl -fsSL "$base/$asset" -o "$work/$asset"

curl -fsSL "$base/checksums.txt" -o "$work/checksums.txt"
expected=$(awk -v asset="$asset" '$2 == asset { print $1 }' "$work/checksums.txt")
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$work/$asset" | cut -d' ' -f1)
else
    actual=$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)
fi
if [ "$expected" != "$actual" ]; then
    echo "checksum mismatch for $asset" >&2
    exit 1
fi
echo "checksum matches"

tar xzf "$work/$asset" -C "$work"
mkdir -p "$INSTALL_DIRECTORY"
replacement=$(mktemp "$INSTALL_DIRECTORY/.monkeys.XXXXXX")
install -m 755 "$work/monkeys" "$replacement"
mv -f "$replacement" "$INSTALL_DIRECTORY/monkeys"
echo "installed $INSTALL_DIRECTORY/monkeys"

case ":$PATH:" in
    *":$INSTALL_DIRECTORY:"*) ;;
    *) echo "$INSTALL_DIRECTORY is not on PATH; add it to your shell startup file" ;;
esac

if [ "$(uname -s)" = "Linux" ] && ! command -v secret-tool >/dev/null 2>&1; then
    echo "monkeys needs secret-tool: libsecret-tools on Debian and Ubuntu, libsecret on Fedora and Arch"
fi
