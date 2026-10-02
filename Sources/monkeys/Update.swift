import Foundation

enum UpdatePlan: Equatable {
    case homebrew(URL)
    case installer(URL)
}

func updatePlan(for executable: URL) -> UpdatePlan {
    let resolved = executable.resolvingSymlinksInPath()
    if let cellar = resolved.path.range(of: "/Cellar/monkeys/") {
        let prefix = String(resolved.path[..<cellar.lowerBound])
        return .homebrew(URL(fileURLWithPath: prefix).appendingPathComponent("bin/brew"))
    }
    return .installer(resolved.deletingLastPathComponent())
}

private func runUpdateCommand(_ arguments: [String], environment: [String: String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw StoreFailure.bundleFailed("update failed: \(arguments[0]) exited with status \(process.terminationStatus)")
    }
}

private func updateWithInstaller(in directory: URL) throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("monkeys-update-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let script = temporary.appendingPathComponent("install.sh")
    var environment = ProcessInfo.processInfo.environment
    environment["INSTALL_DIRECTORY"] = directory.path
    environment.removeValue(forKey: "MONKEYS_VERSION")
    try runUpdateCommand(["curl", "-fsSL", "https://monk3ys.dev/install", "-o", script.path], environment: environment)
    try runUpdateCommand(["sh", script.path], environment: environment)
}

func runUpdate(_ arguments: [String]) throws {
    guard arguments.isEmpty else { throw StoreFailure.badInvocation("monkeys update, or monkeys upgrade") }
    guard let executable = Bundle.main.executableURL else {
        throw StoreFailure.bundleFailed("cannot locate the running monkeys executable to update it")
    }
    switch updatePlan(for: executable) {
    case .homebrew(let brew):
        printToStandardError("updating monkeys through Homebrew")
        try runUpdateCommand([brew.path, "upgrade", "eastriverlee/tap/monkeys"], environment: ProcessInfo.processInfo.environment)
    case .installer(let directory):
        printToStandardError("updating " + directory.appendingPathComponent("monkeys").path)
        try updateWithInstaller(in: directory)
    }
}
