import Foundation
import Testing
@testable import monkeys

@Test(arguments: ["/opt/homebrew", "/usr/local", "/home/linuxbrew/.linuxbrew"])
func detectsHomebrewInstallations(prefix: String) {
    let executable = URL(fileURLWithPath: prefix + "/Cellar/monkeys/1.5.0/bin/monkeys")
    #expect(updatePlan(for: executable) == .homebrew(URL(fileURLWithPath: prefix + "/bin/brew")))
}

@Test func resolvesSymlinksToTheInstalledExecutable() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("monkeys")
    try Data().write(to: executable)
    let alias = directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: executable)
    #expect(updatePlan(for: alias) == .installer(directory.resolvingSymlinksInPath()))
}
