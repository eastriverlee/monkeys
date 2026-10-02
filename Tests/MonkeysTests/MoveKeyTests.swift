import Foundation
import Testing
@testable import monkeys

private struct FileSecretStore: SecretStore {
    let path: URL
    var failsRemoval = false

    func contents() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: path))
    }

    func store(_ value: String, forName name: String) throws {
        var stored = try contents()
        stored[name] = value
        try JSONEncoder().encode(stored).write(to: path)
    }

    func read(forName name: String) throws -> String {
        guard let value = try contents()[name] else { throw StoreFailure.keyNotStored(name) }
        return value
    }

    func remove(forName name: String) throws {
        guard !failsRemoval else { throw StoreFailure.backendFailed("test removal failure") }
        var stored = try contents()
        stored.removeValue(forKey: name)
        try JSONEncoder().encode(stored).write(to: path)
    }

    func storedKeys() throws -> [String] {
        Array(try contents().keys)
    }
}

private struct MoveFixture {
    let directory: URL
    let project: Project
    let store: FileSecretStore

    init(_ contents: String, secrets: [String: String] = [:]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(projectFileName)
        try contents.write(to: path, atomically: true, encoding: .utf8)
        project = try parseProject(at: path.path, directory: directory.path)
        store = FileSecretStore(path: directory.appendingPathComponent("store.json"))
        try JSONEncoder().encode(secrets).write(to: store.path)
    }

    func scope(_ profile: String) -> Scope {
        Scope(profile: "example." + profile, project: project)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func updatedProject() throws -> Project {
        try parseProject(at: project.path, directory: directory.path)
    }
}

@Test func movesSecretBetweenProfilesAndChangesKeyName() throws {
    let fixture = try MoveFixture("+example\n@test\nOLD_KEY\n@production\n", secrets: ["example.test/OLD_KEY": "synthetic"])
    defer { try? fixture.remove() }
    let move = KeyMove(source: fixture.scope("test"), sourceKey: "OLD_KEY",
                       target: fixture.scope("production"), targetKey: "NEW_KEY")
    try moveKey(move, store: fixture.store)
    #expect(try fixture.store.contents() == ["example.production/NEW_KEY": "synthetic"])
    let project = try fixture.updatedProject()
    #expect(project.keys(for: "example.test").isEmpty)
    #expect(project.keys(for: "example.production") == ["NEW_KEY"])
}

@Test(arguments: [true, false]) func movesBetweenGlobalAndProfile(isSourceGlobal: Bool) throws {
    let fixture = try MoveFixture("+example\n@test\n", secrets: [isSourceGlobal ? "KEY" : "example.test/KEY": "synthetic"])
    defer { try? fixture.remove() }
    let source = isSourceGlobal ? Scope.noProfile : fixture.scope("test")
    let target = isSourceGlobal ? fixture.scope("test") : Scope.noProfile
    try moveKey(KeyMove(source: source, sourceKey: "KEY", target: target, targetKey: "KEY"), store: fixture.store)
    #expect(try fixture.store.contents() == [target.storedName("KEY"): "synthetic"])
    #expect(try fixture.updatedProject().keys(for: "example.test") == (isSourceGlobal ? ["KEY"] : []))
}

@Test func movesPublicValueWithoutTurningItIntoASecret() throws {
    let fixture = try MoveFixture("+example\n@test\nPORT=3000\n@production\n")
    defer { try? fixture.remove() }
    try moveKey(KeyMove(source: fixture.scope("test"), sourceKey: "PORT",
                        target: fixture.scope("production"), targetKey: "HTTP_PORT"), store: fixture.store)
    let project = try fixture.updatedProject()
    #expect(project.value(of: "PORT", for: "example.test") == nil)
    #expect(project.value(of: "HTTP_PORT", for: "example.production") == "3000")
    #expect(try fixture.store.contents().isEmpty)
}

@Test(arguments: ["NEW_KEY", "NEW_KEY=occupied", ""]) func refusesOccupiedTargets(declaration: String) throws {
    let secrets = declaration.isEmpty
        ? ["example.test/OLD_KEY": "synthetic", "example.test/NEW_KEY": "occupied"]
        : ["example.test/OLD_KEY": "synthetic"]
    let contents = "+example\n@test\nOLD_KEY\n" + declaration + "\n"
    let fixture = try MoveFixture(contents, secrets: secrets)
    defer { try? fixture.remove() }
    let move = KeyMove(source: fixture.scope("test"), sourceKey: "OLD_KEY",
                       target: fixture.scope("test"), targetKey: "NEW_KEY")
    #expect(throws: StoreFailure.self) { try moveKey(move, store: fixture.store) }
    #expect(try fixture.store.contents() == secrets)
    #expect(try String(contentsOfFile: fixture.project.path, encoding: .utf8) == contents)
}

@Test func refusesSharedDeclarationsBeforeMovingSecrets() throws {
    let contents = "+example\n@test,production\nKEY\n"
    let secrets = ["example.test/KEY": "synthetic"]
    let fixture = try MoveFixture(contents, secrets: secrets)
    defer { try? fixture.remove() }
    let move = KeyMove(source: fixture.scope("test"), sourceKey: "KEY",
                       target: Scope.noProfile, targetKey: "KEY")
    #expect(throws: StoreFailure.self) { try moveKey(move, store: fixture.store) }
    #expect(try fixture.store.contents() == secrets)
    #expect(try String(contentsOfFile: fixture.project.path, encoding: .utf8) == contents)
}

@Test func leavesDeclarationsUnchangedWhenSourceRemovalFails() throws {
    let contents = "+example\n@test\nKEY\n@production\n"
    let fixture = try MoveFixture(contents, secrets: ["example.test/KEY": "synthetic"])
    defer { try? fixture.remove() }
    var store = fixture.store
    store.failsRemoval = true
    let move = KeyMove(source: fixture.scope("test"), sourceKey: "KEY",
                       target: fixture.scope("production"), targetKey: "KEY")
    #expect(throws: StoreFailure.self) { try moveKey(move, store: store) }
    #expect(try store.read(forName: "example.test/KEY") == "synthetic")
    #expect(try store.read(forName: "example.production/KEY") == "synthetic")
    #expect(try String(contentsOfFile: fixture.project.path, encoding: .utf8) == contents)
}

@Test(arguments: [
    ["@outside.test", "OLD_KEY", "@outside.production"],
    ["@outside.test", "OLD_KEY", "@outside.production", "NEW_KEY"],
    ["@", "OLD_KEY", "@outside.production"],
    ["@outside.test", "OLD_KEY", "@"],
    ["@outside.test", "OLD_KEY", "NEW_KEY"],
]) func parsesKeyMoveEndpoints(arguments: [String]) throws {
    let move = try parseKeyMove(arguments)
    #expect(move.source.profile == (arguments[0] == "@" ? nil : "outside.test"))
    let target = arguments[2]
    let expectedProfile = target == "@" ? nil : target == "NEW_KEY" ? "outside.test" : "outside.production"
    #expect(move.target.profile == expectedProfile)
    #expect(move.sourceKey == "OLD_KEY")
    #expect(move.targetKey == (arguments.contains("NEW_KEY") ? "NEW_KEY" : "OLD_KEY"))
}

@Test func movesAnUnrememberedDeclarationWithinItsProfile() throws {
    let fixture = try MoveFixture("+example\n@test\nOLD_KEY\n")
    defer { try? fixture.remove() }
    let scope = fixture.scope("test")
    try moveKey(KeyMove(source: scope, sourceKey: "OLD_KEY", target: scope, targetKey: "NEW_KEY"), store: fixture.store)
    #expect(try fixture.updatedProject().keys(for: "example.test") == ["NEW_KEY"])
    #expect(try fixture.store.contents().isEmpty)
}

@Test func selectsAndDeletesOnlyUntrackedKeysInTheNamespace() throws {
    let secrets = ["example.test/TRACKED": "synthetic", "example.test/LEFTOVER": "synthetic",
                   "example.old/OLD_KEY": "synthetic", "other.test/KEY": "synthetic",
                   "example2.test/KEY": "synthetic", "GLOBAL_KEY": "synthetic"]
    let fixture = try MoveFixture("+example\n@test\nTRACKED\nPORT=3000\n", secrets: secrets)
    defer { try? fixture.remove() }
    let keys = untrackedKeys(in: fixture.project, stored: try fixture.store.storedKeys())
    #expect(keys.map(\.storedName) == ["example.old/OLD_KEY", "example.test/LEFTOVER"])
    try removeUntrackedKeys(keys, store: fixture.store)
    #expect(try fixture.store.contents() == secrets.filter { !keys.map(\.storedName).contains($0.key) })
    #expect(try fixture.updatedProject().keys(for: "example.test") == ["TRACKED"])
}

@Test func doctorShowsUntrackedKeysAsNeutralAndKeepsMissingStatus() throws {
    let fixture = try MoveFixture("+example\n@test\nTRACKED\nMISSING\nPORT=3000\n")
    defer { try? fixture.remove() }
    let stored = ["example.test/TRACKED", "example.test/LEFTOVER", "example.old/OLD_KEY", "other.test/KEY"]
    let report = doctorReport(in: fixture.project, stored: stored, isShort: false)
    #expect(report.hasMissingKeys)
    #expect(report.lines.contains { $0.contains("- LEFTOVER") })
    #expect(report.lines.contains { $0.contains("- OLD_KEY") })
    #expect(!report.lines.contains { $0.contains("other") })
    #expect(report.lines.contains { $0.contains("✓ TRACKED") })
    #expect(report.lines.contains { $0.contains("✗ MISSING") })
    let short = doctorReport(in: fixture.project, stored: stored, isShort: true)
    #expect(short.lines == ["missing @test: MISSING"])
}

@Test func untrackedKeysDoNotMakeDoctorFailAndPublicKeysAreTracked() throws {
    let fixture = try MoveFixture("+example\n@test\nPORT=3000\n")
    defer { try? fixture.remove() }
    let stored = ["example.test/PORT", "example.test/LEFTOVER"]
    #expect(untrackedKeys(in: fixture.project, stored: stored).map(\.key) == ["LEFTOVER"])
    let report = doctorReport(in: fixture.project, stored: stored, isShort: true)
    #expect(!report.hasMissingKeys)
    #expect(report.lines.isEmpty)
}
