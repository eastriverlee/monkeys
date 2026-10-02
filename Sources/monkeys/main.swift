import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func printToStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func isTerminal(_ descriptor: Int32) -> Bool {
    isatty(descriptor) != 0
}

func printHintToTerminal(_ message: String) {
    guard isTerminal(STDERR_FILENO) else { return }
    printToStandardError(message)
}

func isSetInThisEnvironment(_ name: String) -> Bool {
    ProcessInfo.processInfo.environment[name] != nil
}

func askYesOrNo(_ question: String) -> Bool {
    guard isTerminal(STDIN_FILENO), isTerminal(STDERR_FILENO) else { return false }
    FileHandle.standardError.write(Data((question + " " + messageStyle("[y/N]", .bold) + " ").utf8))
    guard let answer = readLine(strippingNewline: true)?.lowercased() else { return false }
    return answer == "y" || answer == "yes"
}

/** The vault has no undo, so anything that empties it asks a person first. */
func confirmedForget(_ what: String) throws {
    guard isTerminal(STDIN_FILENO), isTerminal(STDERR_FILENO) else {
        throw StoreFailure.forgetRefused("nothing forgotten. this asks first, so it needs a terminal")
    }
    guard askYesOrNo("\(what). go ahead?") else {
        throw StoreFailure.forgetRefused("nothing forgotten")
    }
}

func askForWord(_ question: String, _ word: String) -> Bool {
    guard isTerminal(STDIN_FILENO), isTerminal(STDERR_FILENO) else { return false }
    FileHandle.standardError.write(
        Data((question + " " + messageStyle("[" + word + "/N]", .bold) + " ").utf8))
    guard let answer = readLine(strippingNewline: true) else { return false }
    return answer.trimmingCharacters(in: .whitespaces) == word
}

func readSecretFromInput() -> String {
    if !isTerminal(STDIN_FILENO) {
        let piped = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: piped, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let entered = getpass("secret: ") else { return "" }
    return String(cString: entered)
}

private let clipboardReaders: [[String]] = [
    ["pbpaste"],
    ["wl-paste", "--no-newline"],
    ["xclip", "-selection", "clipboard", "-o"],
    ["xsel", "--clipboard", "--output"],
]

private let clipboardWriters: [[String]] = [
    ["pbcopy"],
    ["wl-copy"],
    ["xclip", "-selection", "clipboard"],
    ["xsel", "--clipboard", "--input"],
]

func hasClipboard() -> Bool {
    clipboardWriters.contains { executable(named: $0[0]) != nil }
}

func writeToClipboard(_ text: String) throws {
    guard let writer = clipboardWriters.first(where: { executable(named: $0[0]) != nil }),
          let tool = executable(named: writer[0]) else {
        throw StoreFailure.bundleFailed("no clipboard tool found; install wl-clipboard, xclip or xsel")
    }
    let process = Process()
    let input = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = Array(writer.dropFirst())
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    input.fileHandleForWriting.write(Data(text.utf8))
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw StoreFailure.bundleFailed("\(writer[0]) failed to take the passphrase")
    }
}

private func executable(named name: String) -> String? {
    let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    return directories.lazy.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func readSecretFromClipboard() throws -> String {
    guard let reader = clipboardReaders.first(where: { executable(named: $0[0]) != nil }),
          let tool = executable(named: reader[0]) else {
        throw StoreFailure.bundleFailed("no clipboard tool found; install wl-clipboard, xclip or xsel")
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = Array(reader.dropFirst())
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let pasted = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: pasted, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func requireKey(_ arguments: [String]) throws -> String {
    guard let name = arguments.first else { throw StoreFailure.invalidKey("") }
    guard isValidKey(name) else { throw StoreFailure.invalidKey(name) }
    guard arguments.count == 1 else {
        throw StoreFailure.bundleFailed("one key at a time, and no secret on the line")
    }
    return name
}

func spendHint(_ scope: Scope, _ name: String) -> String {
    if let keys = scope.projectKeys, keys.contains(name) { return "monkeys run <command>" }
    return "monkeys run \(scope.profileArgument)\(name) <command>"
}

func readValueFromInput() -> String {
    if !isTerminal(STDIN_FILENO) {
        let piped = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: piped, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    FileHandle.standardError.write(Data("value: ".utf8))
    return readLine(strippingNewline: true) ?? ""
}

private func setPublicValue(_ given: Scope, _ chosen: ProfileArgument, _ name: String, readsClipboard: Bool) throws {
    if let project = given.project, let profile = given.profile, project.keys(for: profile).contains(name) {
        throw StoreFailure.keyIsSecret(name, project.shortName(profile))
    }
    let value = readsClipboard ? try readSecretFromClipboard() : readValueFromInput()
    guard !value.isEmpty else { throw StoreFailure.emptyValue }
    let scope = given.project == nil ? (try makingProjectFile(chosen) ?? given) : given
    guard let project = scope.project, let profile = scope.profile else { throw StoreFailure.valuesNeedProject }
    try writeValue(value, forKey: name, profile: profile, in: project)
    printToStandardError(messageStyle("wrote", .good) + " " + messageStyle(name + "=" + value, .bold) + " to \(projectFileName) for @\(project.shortName(profile))")
}

private func rejectingProfileList(_ arguments: [String]) throws {
    guard let first = arguments.first, first.hasPrefix("@"), first.contains(",") else { return }
    let one = first.dropFirst().split(separator: ",").first.map(String.init) ?? ""
    throw StoreFailure.bundleFailed("remember walks one profile at a time: monkeys remember @\(one)")
}

private let firstProfileName = "test"

private func makingProjectFile(_ chosen: ProfileArgument) throws -> Scope? {
    guard case .none = chosen else { return nil }
    guard let root = checkoutRoot(), let namespace = namespaceFromDirectory(root) else { return nil }
    let path = root + "/" + projectFileName
    try ("+" + namespace + "\n@" + firstProfileName + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    let shown = root == FileManager.default.currentDirectoryPath ? projectFileName : abbreviatingHome(path)
    printToStandardError(messageStyle("made", .good) + " " + messageStyle(shown, .bold)
        + " for " + messageStyle("+" + namespace + " @" + firstProfileName, .argument))
    return try scope(for: chosen)
}

private func requireListable(_ key: String, in scope: Scope) throws {
    guard let project = scope.project, let profile = scope.profile else { return }
    guard project.profiles.contains(profile), !project.keys(for: profile).contains(key) else { return }
    _ = try project.writablePath()
}

func listKey(_ key: String, in scope: Scope) throws {
    guard let project = scope.project, let profile = scope.profile else { return }
    guard project.profiles.contains(profile), !project.keys(for: profile).contains(key) else { return }
    try writeKey(key, profile: profile, in: project)
    printToStandardError(messageStyle("listed", .good) + " " + messageStyle(key, .bold)
        + " in \(projectFileName) for @\(project.shortName(profile))")
}

func runSet(_ arguments: [String]) throws {
    let readsClipboard = arguments.contains("--clipboard")
    let isPublic = arguments.contains("--public")
    let walksAll = arguments.contains("--all")
    let positional = arguments.filter { $0 != "--clipboard" && $0 != "--public" && $0 != "--all" }
    try rejectingProfileList(positional)
    let (chosen, rest) = try takeProfileArgument(positional)
    var scope = try scope(for: chosen)
    guard !rest.isEmpty else {
        guard !readsClipboard else {
            throw StoreFailure.bundleFailed("--clipboard remembers one key: monkeys remember <KEY> --clipboard")
        }
        guard !isPublic else { throw StoreFailure.badInvocation("monkeys remember --public [@profile] <KEY>") }
        try walkProfile(scope, walksAll: walksAll)
        return
    }
    guard !walksAll else { throw StoreFailure.badInvocation(walkForm) }
    let name = try requireKey(rest)
    if isPublic { return try setPublicValue(scope, chosen, name, readsClipboard: readsClipboard) }
    if let project = scope.project, let profile = scope.profile, project.value(of: name, for: profile) != nil {
        throw StoreFailure.keyIsValue(name, project.shortName(profile))
    }
    try requireListable(name, in: scope)
    let value = readsClipboard ? try readSecretFromClipboard() : readSecretFromInput()
    guard !value.isEmpty else { throw StoreFailure.emptySecret }
    if scope.project == nil, let made = try makingProjectFile(chosen) { scope = made }
    try secretStore.store(value, forName: scope.storedName(name))
    printToStandardError(messageStyle("remembered", .good) + " " + messageStyle(scope.storedName(name), .bold))
    try listKey(name, in: scope)
    printHintToTerminal(messageStyle("give it to a command with:", .dim))
    printHintToTerminal("  " + messageStyle(spendHint(scope, name), .argument))
}

func runForget(_ arguments: [String]) throws {
    if arguments.contains("--all") || arguments.contains("--untracked") {
        return try runForgetUntracked(arguments)
    }
    if arguments.count == 1, let only = arguments.first, only.hasPrefix("@") || only.hasPrefix("+") {
        return try runForgetProfiles(only)
    }
    let (scope, rest) = try resolveScope(arguments)
    let name = try requireKey(rest)
    if let project = scope.project, let profile = scope.profile, project.value(of: name, for: profile) != nil {
        _ = try removeValue(forKey: name, profile: profile, in: project)
        printToStandardError(messageStyle("forgot", .good) + " " + messageStyle(name, .bold) + " from \(projectFileName) for @\(project.shortName(profile))")
        return
    }
    try confirmedForget("forget \(scope.storedName(name)), which nothing else holds")
    try secretStore.remove(forName: scope.storedName(name))
    printToStandardError(messageStyle("forgot", .good) + " " + messageStyle(scope.storedName(name), .bold))
    guard isSetInThisEnvironment(name) else { return }
    printHintToTerminal(messageStyle("this shell still carries it; clear it with:", .dim))
    printHintToTerminal("  " + messageStyle("unset \(name)", .argument))
}

func runDrop(_ arguments: [String]) throws {
    if let only = arguments.first, only.hasPrefix("@") || only.hasPrefix("+"), arguments.count == 1 {
        throw StoreFailure.forgetRefused(
            "drop takes one key: monkeys drop \(only) <KEY>. to empty a profile's vault, monkeys forget \(only)")
    }
    let (scope, rest) = try resolveScope(arguments)
    let name = try requireKey(rest)
    guard let project = scope.project, let profile = scope.profile, project.profiles.contains(profile) else {
        return try runForget(arguments)
    }
    if project.value(of: name, for: profile) != nil { return try runForget(arguments) }
    let listed = project.keys(for: profile).contains(name)
    if listed { _ = try canRemoveKey(name, profile: profile, in: project) }
    let held = (try? storedKeysInScope(scope))?.contains(name) ?? true
    try confirmedForget(
        held
            ? "forget \(scope.storedName(name)), which nothing else holds, and unlist it from \(projectFileName)"
            : "unlist \(name) from \(projectFileName), which the vault has nothing under")
    var forgotten = true
    do {
        try secretStore.remove(forName: scope.storedName(name))
    } catch {
        guard listed else { throw error }
        forgotten = false
    }
    if forgotten {
        printToStandardError(messageStyle("forgot", .good) + " " + messageStyle(scope.storedName(name), .bold))
    }
    guard try removeKey(name, profile: profile, in: project) else {
        throw StoreFailure.forgetRefused("\(name) is not listed in \(projectFileName) for @\(project.shortName(profile))")
    }
    printToStandardError(messageStyle("unlisted", .good) + " " + messageStyle(name, .bold)
        + " from \(projectFileName) for @\(project.shortName(profile))")
}

func runList() throws {
    let stored = try secretStore.storedKeys()
    guard !stored.isEmpty else {
        printToStandardError("nothing remembered")
        return
    }
    var keysByProfile: [String: [String]] = [:]
    for name in stored {
        guard let slash = name.firstIndex(of: "/") else {
            keysByProfile["", default: []].append(name)
            continue
        }
        keysByProfile[String(name[..<slash]), default: []].append(String(name[name.index(after: slash)...]))
    }
    for (index, profile) in keysByProfile.keys.sorted().enumerated() {
        if index > 0 { print() }
        print(outputStyle("@" + profile, .good, .bold))
        for key in keysByProfile[profile]!.sorted() { print(outputStyle(key, .argument)) }
    }
}

func validatedKeys(_ scope: Scope, _ rest: [String]) throws -> [String] {
    let given = rest.flatMap { $0.split(separator: ",").map(String.init) }
    let keys = given.isEmpty ? try keysInScope(scope) : given
    for name in keys where !isValidKey(name) { throw StoreFailure.invalidKey(name) }
    return keys
}

func runPreview(_ arguments: [String]) throws {
    let (scope, rest) = try resolveScope(arguments)
    let given = try validatedKeys(scope, rest)
    let values = try publicValues(scope, given: rest.isEmpty ? nil : given)
    let secrets = given.filter { name in !values.contains { $0.key == name } }
    guard let width = (secrets + values.map(\.key)).map(\.count).max() else { return }
    for name in secrets {
        let masked = maskedValue(try secretStore.read(forName: scope.storedName(name)))
        print(name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + masked)
    }
    for entry in values {
        print(entry.key.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + entry.value)
    }
}

private func publicValues(_ scope: Scope, given: [String]?) throws -> [ValueEntry] {
    guard let project = scope.project, let profile = scope.profile else { return [] }
    let entries = project.values(for: profile)
    guard let given else { return entries }
    return entries.filter { given.contains($0.key) }
}

private let packForm = "monkeys pack [name] [--path DIR] [--open] [--only [KEY[,KEY...]] [@profile[,profile...] [KEY[,KEY...]]]...]"

private let profileNeeded = "a bundle carries a profile: run this in a project with a \(projectFileName) file, or name one with --only @profile"

private func keysIn(_ token: String) throws -> [String] {
    let keys = token.split(separator: ",").map(String.init)
    guard !keys.isEmpty, keys.allSatisfy(isValidKey) else { throw StoreFailure.badInvocation(packForm) }
    return keys
}

private func resolvedProfiles(_ argument: String, in project: Project?) throws -> [String] {
    let pieces = argument.dropFirst().split(separator: ",").map { $0.hasPrefix("@") ? String($0.dropFirst()) : String($0) }
    guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty }) else { throw StoreFailure.badInvocation(packForm) }
    return try pieces.map { name in
        guard let project else {
            guard isValidProfileName(name) else { throw StoreFailure.invalidProfileName("@" + name) }
            return name
        }
        return try project.profile(matching: name)
    }
}

private func coalesced(_ blocks: [Block]) -> [Block] {
    blocks.reduce(into: []) { result, block in
        if let last = result.last, last.profiles == block.profiles {
            result[result.count - 1] = Block(profiles: last.profiles, keys: last.keys + block.keys)
        } else {
            result.append(block)
        }
    }
}

private func restricted(_ blocks: [Block], toProfiles profiles: [String]) -> [Block] {
    coalesced(blocks.compactMap { block in
        let kept = block.profiles.filter(profiles.contains)
        return kept.isEmpty ? nil : Block(profiles: kept, keys: block.keys)
    })
}

private func restricted(_ blocks: [Block], toNames keys: [String]) -> [Block] {
    blocks.compactMap { block in
        let kept = block.keys.filter(keys.contains)
        return kept.isEmpty ? nil : Block(profiles: block.profiles, keys: kept)
    }
}

private func storedBlocks(for profiles: [String]) throws -> [Block] {
    try profiles.map { Block(profiles: [$0], keys: try storedKeysInScope(Scope(profile: $0, project: nil))) }
}

private func selectedBlocks(_ tokens: [String], from written: [Block], defaultingTo scope: [String], project: Project?) throws -> [Block] {
    var blocks: [Block] = []
    var open: [String]?
    var openNames: [String] = []
    var leading: [String] = []
    func closeOpen() throws {
        guard let profiles = open else { return }
        if !openNames.isEmpty {
            blocks.append(Block(profiles: profiles, keys: openNames))
        } else if project == nil {
            blocks += try storedBlocks(for: profiles)
        } else {
            blocks += restricted(written, toProfiles: profiles)
        }
        open = nil
        openNames = []
    }
    for token in tokens {
        if token.hasPrefix("@") {
            try closeOpen()
            open = try resolvedProfiles(token, in: project)
            continue
        }
        let keys = try keysIn(token)
        guard open != nil else {
            guard blocks.isEmpty else { throw StoreFailure.badInvocation(packForm) }
            leading += keys
            continue
        }
        openNames += keys
    }
    try closeOpen()
    guard leading.isEmpty || blocks.isEmpty else { throw StoreFailure.badInvocation(packForm) }
    guard !leading.isEmpty else { return blocks.isEmpty ? written : blocks }
    let base = restricted(written, toProfiles: scope)
    for name in leading where !base.contains(where: { $0.keys.contains(name) }) {
        let shown = scope.map { shortened($0, in: project?.namespace) }.joined(separator: ",")
        throw StoreFailure.bundleFailed("\(name) is not listed for @\(shown), so there is nothing to pack under that key")
    }
    return restricted(base, toNames: leading)
}

private func packedBlocks(_ arguments: [String]) throws -> (blocks: [Block], project: Project?, fileName: String?) {
    let (chosen, afterProfile) = try takeProfileArgument(arguments)
    let project = try locateProject()
    var rest = afterProfile
    var selection: [String] = []
    if let flag = rest.firstIndex(of: "--only") {
        selection = Array(rest[(flag + 1)...])
        rest.removeSubrange(flag...)
    }
    guard rest.count <= 1 else { throw StoreFailure.badInvocation(packForm) }
    switch chosen {
    case .noProfile:
        throw StoreFailure.bundleFailed(profileNeeded)
    case .named(let name):
        throw StoreFailure.bundleFailed("pack picks profiles after --only: monkeys pack --only @\(name)")
    case .none:
        guard let project else {
            guard selection.contains(where: { $0.hasPrefix("@") }) else { throw StoreFailure.bundleFailed(profileNeeded) }
            return (try selectedBlocks(selection, from: [], defaultingTo: [], project: nil), nil, rest.first)
        }
        return (try selectedBlocks(selection, from: project.blocks, defaultingTo: [project.defaultProfile], project: project), project, rest.first)
    }
}

private func filledBlock(_ block: Block, project: Project?) throws -> BundleBlock {
    if let project {
        for profile in block.profiles {
            let listed = project.keys(for: profile)
            if let stray = block.keys.first(where: { !listed.contains($0) }) {
                throw StoreFailure.bundleFailed("\(stray) is not listed for @\(project.shortName(profile)), so there is nothing to pack under that key")
            }
        }
    }
    var entries: [(name: String, values: [String])] = []
    var missing: [String: [String]] = [:]
    for name in block.keys {
        var values: [String] = []
        for profile in block.profiles {
            do {
                values.append(try secretStore.read(forName: profile + "/" + name))
            } catch StoreFailure.keyNotStored {
                missing[profile, default: []].append(name)
            }
        }
        entries.append((name, values))
    }
    for profile in block.profiles {
        if let keys = missing[profile] { throw StoreFailure.keysNotStored(keys, "@\(profile) ") }
    }
    return BundleBlock(profiles: block.profiles, entries: entries)
}

private func blockLines(_ profiles: [[String]], in namespace: String?) -> String {
    let header = namespace.map { "+" + $0 + " " } ?? ""
    return header + profiles.map { "@" + $0.map { shortened($0, in: namespace) }.joined(separator: ",") }.joined(separator: " ")
}

private let personalProfile = "personal"

private func packWithoutPersonal(_ project: Project?) -> String {
    guard let project else { return "" }
    let others = project.profiles.map(project.shortName).filter { $0 != personalProfile }
    guard !others.isEmpty else { return "" }
    return " to pack the rest: monkeys pack --only @" + others.joined(separator: ",")
}

/** @personal is one person's own copy of a key, so a bundle never takes it by itself. */
private func confirmedPersonalSharing(_ profiles: [String], _ project: Project?) throws {
    let shown = profiles.map { project?.shortName($0) ?? $0 }
    guard shown.contains(personalProfile) else { return }
    let question = messageStyle("@personal is yours, not the team's", .bad)
        + ", and a bundle hands it to whoever opens it."
    guard askForWord(question, "UNDERSTOOD") else {
        throw StoreFailure.bundleFailed("nothing written." + packWithoutPersonal(project))
    }
}

func runPack(_ arguments: [String]) throws {
    let opens = arguments.contains("--open")
    let asks = arguments.contains("--ask")
    let (directory, remaining) = try takeDirectoryFlag("--path", arguments)
    let (blocks, project, fileName) = try packedBlocks(remaining.filter { $0 != "--open" && $0 != "--ask" })
    guard !blocks.isEmpty else { throw StoreFailure.bundleFailed("nothing to pack: no keys are listed for that") }
    try confirmedPersonalSharing(blocks.flatMap(\.profiles), project)
    let filled = try blocks.map { try filledBlock($0, project: project) }
    let path = try bundleDestination(fileName, in: directory)
    try confirmedOutOfHarm(
        path,
        "a bundle into " + messageStyle(abbreviatingHome(path), .bold)
            + ", where a commit can take it. go ahead?")
    let namespace = project?.namespace
    let values = packedValues(project, for: filled.flatMap(\.profiles))
    let origin = try writeBundle(ProfileBundle(namespace: namespace, blocks: filled, values: values), to: path, asking: asks)
    let count = filled.reduce(0) { $0 + $1.entries.count * $1.profiles.count }
    let valueCount = values.reduce(0) { $0 + $1.entries.count * $1.profiles.count }
    let valuesNote = valueCount == 0 ? "" : ", \(valueCount) value\(valueCount == 1 ? "" : "s")"
    printToStandardError(messageStyle("wrote", .good) + " " + messageStyle(abbreviatingHome(path), .bold) + ": \(blockLines(filled.map(\.profiles), in: namespace)), \(count) secret\(count == 1 ? "" : "s")\(valuesNote)")
    if origin == .clipboard {
        printToStandardError(messageStyle("copied", .good) + " its passphrase to your clipboard; send that the other way")
    }
    if opens { revealInFileManager(path) }
}

private func packedValues(_ project: Project?, for profiles: [String]) -> [ValueBlock] {
    guard let project else { return [] }
    return project.blocks.compactMap { block in
        let kept = block.profiles.filter(profiles.contains)
        return kept.isEmpty || block.values.isEmpty ? nil : ValueBlock(profiles: kept, entries: block.values)
    }
}

func revealInFileManager(_ path: String) {
    #if os(macOS)
    let command = ["/usr/bin/open", "-R", path]
    #else
    let openers = ["/usr/bin/xdg-open", "/usr/local/bin/xdg-open"]
    guard let opener = openers.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        printToStandardError("xdg-open is not installed, so the folder stays closed")
        return
    }
    let command = [opener, URL(fileURLWithPath: path).deletingLastPathComponent().path]
    #endif
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return }
    process.waitUntilExit()
}

func insideCheckout(_ path: String) -> Bool {
    let holder = URL(fileURLWithPath: path).deletingLastPathComponent()
        .resolvingSymlinksInPath().standardizedFileURL.path
    return gitRoot(above: holder) != nil
}

func confirmedOutOfHarm(_ path: String, _ question: String, understanding: Bool = false) throws {
    guard insideCheckout(path) else { return }
    let allowed = understanding ? askForWord(question, "UNDERSTOOD") : askYesOrNo(question)
    guard allowed else {
        throw StoreFailure.bundleFailed(
            "nothing written. without --path it lands in /tmp, which is where this belongs")
    }
}

let pathFlag = "--path"

func takeDirectoryFlag(_ name: String, _ arguments: [String]) throws -> (directory: String?, rest: [String]) {
    guard let index = arguments.firstIndex(of: name) else { return (nil, arguments) }
    guard index + 1 < arguments.count else {
        throw StoreFailure.bundleFailed("\(name) wants a directory after it: \(name) .")
    }
    let directory = arguments[index + 1]
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw StoreFailure.bundleFailed("\(abbreviatingHome(directory)) is not a directory")
    }
    var rest = arguments
    rest.removeSubrange(index...(index + 1))
    return (directory, rest)
}

func bundleDestination(_ name: String?, in directory: String?) throws -> String {
    let folder = directory ?? "/tmp"
    guard let name else {
        return URL(fileURLWithPath: folder).appendingPathComponent("a" + bundleSuffix).path
    }
    guard !name.contains("/") else {
        throw StoreFailure.bundleFailed("a bundle's name carries no directory; \(pathFlag) chooses where it lands")
    }
    return URL(fileURLWithPath: folder).appendingPathComponent(bundlePath(name)).path
}

func gitRoot(above directory: String) -> String? {
    var directory = directory
    while true {
        if FileManager.default.fileExists(atPath: directory + "/.git") { return directory }
        guard directory != "/" else { return nil }
        directory = URL(fileURLWithPath: directory).deletingLastPathComponent().path
    }
}

func unpackDestination(_ given: String?) throws -> String {
    let current = FileManager.default.currentDirectoryPath
    guard let given else { return gitRoot(above: current) ?? current }
    let directory = URL(fileURLWithPath: given).standardizedFileURL.path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw StoreFailure.bundleFailed("\(given) is not a directory")
    }
    return directory
}

private func described(namespace: String?) -> String {
    namespace.map { "+" + $0 } ?? "no +namespace line"
}

func reconcileProjectFile(namespace: String?, _ blocks: [Block], in directory: String) throws {
    let path = directory + "/" + projectFileName
    let shown = directory == FileManager.default.currentDirectoryPath ? projectFileName : abbreviatingHome(path)
    func counted(_ blocks: [Block]) -> String {
        let total = blocks.reduce(0) { $0 + $1.keys.count }
        return "\(total) key\(total == 1 ? "" : "s")"
    }
    guard FileManager.default.fileExists(atPath: path) else {
        try projectFileContents(namespace: namespace, blocks).write(toFile: path, atomically: true, encoding: .utf8)
        printToStandardError(messageStyle("wrote", .good) + " " + messageStyle(shown, .bold) + ": \(blockLines(blocks.map(\.profiles), in: namespace)), \(counted(blocks))")
        return
    }
    let existing = try parseProject(at: path, directory: directory)
    guard existing.namespace == namespace else {
        throw StoreFailure.bundleFailed("\(shown) has \(described(namespace: existing.namespace)); the bundle has \(described(namespace: namespace)), so its profiles are another project's")
    }
    var additions: [Block] = []
    for block in blocks {
        var order: [[String]] = []
        var profilesMissing: [[String]: [String]] = [:]
        for profile in block.profiles {
            let listed = existing.keys(for: profile)
            let missing = block.keys.filter { !listed.contains($0) }
            guard !missing.isEmpty else { continue }
            if profilesMissing[missing] == nil { order.append(missing) }
            profilesMissing[missing, default: []].append(profile)
        }
        additions += order.map { Block(profiles: profilesMissing[$0]!, keys: $0) }
    }
    guard !additions.isEmpty else {
        printToStandardError("\(shown) already lists these keys")
        return
    }
    try writeBlocks(additions, in: existing)
    printToStandardError(messageStyle("added", .good) + " " + messageStyle(blockLines(additions.map(\.profiles), in: nil), .bold) + " with \(counted(additions)) to \(shown)")
}


func reconcileValueLines(_ blocks: [ValueBlock], in directory: String) throws {
    guard !blocks.isEmpty else { return }
    let project = try parseProject(at: directory + "/" + projectFileName, directory: directory)
    let shown = directory == FileManager.default.currentDirectoryPath ? projectFileName : abbreviatingHome(project.path)
    var written = 0
    var kept = 0
    for block in blocks {
        for entry in block.entries {
            let lacking = block.profiles.filter { project.value(of: entry.key, for: $0) == nil }
            kept += block.profiles.count - lacking.count
            guard !lacking.isEmpty else { continue }
            if lacking.count == block.profiles.count {
                try writeValue(entry.value, forKey: entry.key, profile: lacking[0], block: block.profiles, in: project)
            } else {
                for profile in lacking {
                    try writeValue(entry.value, forKey: entry.key, profile: profile, in: project)
                }
            }
            written += lacking.count
        }
    }
    if written > 0 {
        printToStandardError(messageStyle("wrote", .good) + " " + messageStyle(shown, .bold) + ": \(written) value\(written == 1 ? "" : "s")")
    }
    if kept > 0 {
        printToStandardError("\(shown) already had \(kept) of its value\(kept == 1 ? "" : "s"), left as they were")
    }
}

func runDoctor(_ arguments: [String]) throws {
    let isShort = arguments == ["--short"]
    guard arguments.isEmpty || isShort else { throw StoreFailure.badInvocation("monkeys doctor [--short]") }
    guard let project = try locateProject() else {
        throw StoreFailure.badInvocation("monkeys doctor next to a \(projectFileName) file")
    }
    let report = doctorReport(in: project, stored: try secretStore.storedKeys(), isShort: isShort)
    for line in report.lines { print(line) }
    if report.hasMissingKeys { exit(1) }
}

func runUnpack(_ arguments: [String]) throws {
    let keepsBundle = arguments.contains("--keep")
    let positional = arguments.filter { $0 != "--keep" }
    guard let name = positional.first, positional.count <= 2 else {
        throw StoreFailure.badInvocation("monkeys unpack <name> [directory] [--keep]")
    }
    let destination = try unpackDestination(positional.dropFirst().first)
    let path = bundlePath(name)
    let bundle = try readBundle(from: path)
    try reconcileProjectFile(namespace: bundle.namespace, bundle.blocks.map { Block(profiles: $0.profiles, keys: $0.entries.map(\.name)) }, in: destination)
    try reconcileValueLines(bundle.values, in: destination)
    for block in bundle.blocks {
        var stored: [String] = []
        for entry in block.entries {
            for (profile, value) in zip(block.profiles, entry.values) {
                let name = profile + "/" + entry.name
                try secretStore.store(value, forName: name)
                stored.append(name)
            }
        }
        guard !stored.isEmpty else { continue }
        printToStandardError(messageStyle("remembered", .good) + " " + stored.map { messageStyle($0, .bold) }.joined(separator: ", "))
    }
    guard !keepsBundle else { return }
    guard unlink(path) == 0 else {
        printToStandardError(messageStyle("kept", .bad) + " \(abbreviatingHome(path)): \(String(cString: strerror(errno)))")
        return
    }
    printToStandardError(messageStyle("removed", .good) + " " + messageStyle(abbreviatingHome(path), .bold))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
let rest = Array(arguments.dropFirst())

do {
    switch command {
    case "update", "upgrade": try runUpdate(rest)
    case "remember": try runSet(rest)
    case "drop": try runDrop(rest)
    case "list": try runList()
    case "preview": try runPreview(rest)
    case "forget": try runForget(rest)
    case "pack": try runPack(rest)
    case "run": try runCommandWithSecrets(rest)
    case "unpack": try runUnpack(rest)
    case "eat": try runEat(rest)
    case "poo": try runPoo(rest)
    case "export": try runExport(rest)
    case "doctor": try runDoctor(rest)
    case "fill": try runFill(rest)
    case "move": try runMove(rest)
    case "help", "-h", "--help": print(usage)
    default:
        printToStandardError(messageStyle("unknown command:", .bad) + " \(command)")
        printToStandardError("run " + messageStyle("monkeys help", .argument) + " for the commands")
        exit(2)
    }
} catch let failure as StoreFailure {
    printToStandardError(messageStyle("monkeys:", .bad) + " \(failure)")
    exit(1)
} catch {
    printToStandardError(messageStyle("monkeys:", .bad) + " \(error)")
    exit(1)
}
