import Foundation

#if canImport(Darwin)
import Darwin
@_silgen_name("fork") private func forkProcess() -> pid_t
private let setControllingTerminal: UInt = 0x20007461
private let getWindowSize: UInt = 0x40087468
private let setWindowSize: UInt = 0x80087467
#else
import Glibc
private func forkProcess() -> pid_t { fork() }
@_silgen_name("posix_openpt") private func posix_openpt(_ flags: Int32) -> Int32
@_silgen_name("grantpt") private func grantpt(_ descriptor: Int32) -> Int32
@_silgen_name("unlockpt") private func unlockpt(_ descriptor: Int32) -> Int32
@_silgen_name("ptsname") private func ptsname(_ descriptor: Int32) -> UnsafeMutablePointer<CChar>?
private let setControllingTerminal: UInt = 0x540E
private let getWindowSize: UInt = 0x5413
private let setWindowSize: UInt = 0x5414
#endif

private let chunkSize = 65536

nonisolated(unsafe) private var savedTerminal = termios()
nonisolated(unsafe) private var terminalWasChanged = false
nonisolated(unsafe) private var terminalMaster: Int32 = -1

func restoreTerminal() {
    guard terminalWasChanged else { return }
    tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminal)
    terminalWasChanged = false
}

func exitLike(_ status: Int32) -> Never {
    restoreTerminal()
    let signalNumber = status & 0x7f
    if signalNumber == 0 { exit((status >> 8) & 0xff) }
    signal(signalNumber, SIG_DFL)
    kill(getpid(), signalNumber)
    exit(128 + signalNumber)
}

private func waitFor(_ child: pid_t) -> Int32 {
    var status: Int32 = 0
    while waitpid(child, &status, 0) < 0 && errno == EINTR {}
    return status
}

private func writeAll(_ descriptor: Int32, _ bytes: UnsafeRawBufferPointer) -> Bool {
    var offset = 0
    while offset < bytes.count {
        let written = write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
        if written < 0 {
            if errno == EINTR { continue }
            return false
        }
        offset += written
    }
    return true
}

private func writeAll(_ descriptor: Int32, _ bytes: [UInt8]) -> Bool {
    bytes.withUnsafeBytes { writeAll(descriptor, $0) }
}

private func execute(_ command: [String], _ values: [SpentValue]) -> Never {
    for entry in values { setenv(entry.name, entry.value, 1) }
    var argumentVector = command.map { strdup($0) } + [nil]
    execvp(command[0], &argumentVector)
    _ = writeAll(STDERR_FILENO, Array("monkeys: cannot run \(command[0]): \(String(cString: strerror(errno)))\n".utf8))
    _exit(127)
}

private final class Forwarder: @unchecked Sendable {
    private let source: Int32
    private let destination: Int32
    private var redactor: Redactor
    private let completion = DispatchSemaphore(value: 0)

    init(from source: Int32, to destination: Int32, _ values: [SpentValue], showsPlaceholders: Bool) {
        self.source = source
        self.destination = destination
        redactor = Redactor(values, showsPlaceholders: showsPlaceholders)
    }

    func start() {
        Thread { self.forward() }.start()
    }

    private func forward() {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 16)
        var output: [UInt8] = []
        output.reserveCapacity(chunkSize * 2)
        while true {
            let count = read(source, buffer, chunkSize)
            if count < 0 && errno == EINTR { continue }
            output.removeAll(keepingCapacity: true)
            if count <= 0 {
                redactor.flush(into: &output)
                _ = writeAll(destination, output)
                break
            }
            redactor.scan(UnsafeRawBufferPointer(start: buffer, count: count), into: &output)
            guard writeAll(destination, output) else { break }
        }
        close(source)
        completion.signal()
    }

    func join() { completion.wait() }
}

private final class InputRelay: @unchecked Sendable {
    private let master: Int32

    init(to master: Int32) {
        self.master = master
    }

    func start() {
        Thread { self.relay() }.start()
    }

    private func relay() {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 16)
        while true {
            let count = read(STDIN_FILENO, buffer, chunkSize)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            guard writeAll(master, UnsafeRawBufferPointer(start: buffer, count: count)) else { return }
        }
        var endOfFile: UInt8 = 4
        _ = write(master, &endOfFile, 1)
    }
}

private func runThroughPipes(_ command: [String], _ values: [SpentValue]) -> Int32 {
    var standardOutput: [Int32] = [0, 0]
    var standardError: [Int32] = [0, 0]
    guard pipe(&standardOutput) == 0, pipe(&standardError) == 0 else { exitLike(1 << 8) }

    let child = forkProcess()
    if child == 0 {
        dup2(standardOutput[1], STDOUT_FILENO)
        dup2(standardError[1], STDERR_FILENO)
        for descriptor in standardOutput + standardError { close(descriptor) }
        execute(command, values)
    }
    close(standardOutput[1])
    close(standardError[1])
    signal(SIGINT, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    signal(SIGPIPE, SIG_IGN)

    let forwarders = [
        Forwarder(from: standardOutput[0], to: STDOUT_FILENO, values, showsPlaceholders: false),
        Forwarder(from: standardError[0], to: STDERR_FILENO, values, showsPlaceholders: false),
    ]
    for forwarder in forwarders { forwarder.start() }
    for forwarder in forwarders { forwarder.join() }
    return waitFor(child)
}

private func openTerminalPair() -> (master: Int32, slaveName: String)? {
    let master = posix_openpt(O_RDWR | O_NOCTTY)
    guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else { return nil }
    return (master, String(cString: name))
}

private func copyWindowSize() {
    var size = winsize()
    guard ioctl(STDIN_FILENO, getWindowSize, &size) == 0 else { return }
    _ = ioctl(terminalMaster, setWindowSize, &size)
}

private func enterRawMode() {
    guard isTerminal(STDIN_FILENO), tcgetattr(STDIN_FILENO, &savedTerminal) == 0 else { return }
    var raw = savedTerminal
    cfmakeraw(&raw)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    terminalWasChanged = true
    for number in [SIGTERM, SIGHUP] {
        signal(number) { number in
            restoreTerminal()
            signal(number, SIG_DFL)
            kill(getpid(), number)
        }
    }
}

private func runThroughTerminal(_ command: [String], _ values: [SpentValue]) -> Int32 {
    guard let (master, slaveName) = openTerminalPair() else {
        _ = writeAll(STDERR_FILENO, Array("monkeys: cannot allocate a terminal: \(String(cString: strerror(errno)))\n".utf8))
        exit(1)
    }
    terminalMaster = master
    copyWindowSize()

    let child = forkProcess()
    if child == 0 {
        setsid()
        let slave = open(slaveName, O_RDWR)
        _ = ioctl(slave, setControllingTerminal, 0)
        for target in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] { dup2(slave, target) }
        close(slave)
        close(master)
        execute(command, values)
    }
    enterRawMode()
    signal(SIGWINCH) { _ in copyWindowSize() }
    signal(SIGPIPE, SIG_IGN)

    let output = Forwarder(from: master, to: STDOUT_FILENO, values, showsPlaceholders: true)
    let input = InputRelay(to: master)
    output.start()
    input.start()
    output.join()
    return waitFor(child)
}

func runRedacted(_ command: [String], _ values: [SpentValue]) -> Int32 {
    if isTerminal(STDOUT_FILENO) { return runThroughTerminal(command, values) }
    return runThroughPipes(command, values)
}
