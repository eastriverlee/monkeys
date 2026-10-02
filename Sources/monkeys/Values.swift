import Foundation

struct ValueEntry {
    let key: String
    let value: String
}

struct ValueBlock {
    let profiles: [String]
    let entries: [ValueEntry]
}

func spentValues(of project: Project?, for profile: String?) -> [SpentValue] {
    guard let project, let profile else { return [] }
    return project.values(for: profile).map { SpentValue(name: $0.key, value: $0.value) }
}

private func profileLine(_ profiles: [String], in namespace: String?) -> String {
    "@" + profiles.map { shortened($0, in: namespace) }.joined(separator: ",")
}

private struct ValueLineLocation {
    let index: Int
    let profiles: [String]
}

private func locate(_ key: String, for profile: String, in lines: [String], of project: Project) -> ValueLineLocation? {
    var open: [String] = []
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") {
            open = trimmed.dropFirst().split(separator: ",").map { prefixed($0.trimmingCharacters(in: .whitespaces), with: project.namespace) }
            continue
        }
        guard open.contains(profile), let found = splitValueLine(trimmed), found.key == key else { continue }
        return ValueLineLocation(index: index, profiles: open)
    }
    return nil
}

private func rejectingSharedBlock(_ location: ValueLineLocation, _ key: String, _ profile: String, _ project: Project) throws {
    guard location.profiles.count > 1 else { return }
    let shown = location.profiles.map { "@" + project.shortName($0) }.joined(separator: ",")
    throw StoreFailure.bundleFailed("\(key) is set for \(shown) together in \(projectFileName); split that block by hand to change it for @\(project.shortName(profile)) alone")
}

private func fileLines(at path: String) throws -> [String] {
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" { lines.removeLast() }
    return lines
}

private func writeLines(_ lines: [String], to path: String) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

func writeValue(_ value: String, forKey key: String, profile: String, in project: Project) throws {
    try writeValue(value, forKey: key, profile: profile, block: [profile], in: project)
}

func writeValue(_ value: String, forKey key: String, profile: String, block profiles: [String], in project: Project) throws {
    var lines = try fileLines(at: try project.writablePath())
    let line = key + "=" + value
    if let location = locate(key, for: profile, in: lines, of: project) {
        try rejectingSharedBlock(location, key, profile, project)
        lines[location.index] = line
    } else if let block = lines.lastIndex(of: profileLine(profiles, in: project.namespace)) {
        var end = block + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("@") { end += 1 }
        while end > block + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        lines.insert(line, at: end)
    } else {
        lines += [profileLine(profiles, in: project.namespace), line]
    }
    try writeLines(lines, to: try project.writablePath())
}

func removeValue(forKey key: String, profile: String, in project: Project) throws -> Bool {
    var lines = try fileLines(at: try project.writablePath())
    guard let location = locate(key, for: profile, in: lines, of: project) else { return false }
    try rejectingSharedBlock(location, key, profile, project)
    lines.remove(at: location.index)
    try writeLines(lines, to: try project.writablePath())
    return true
}

private func locateKey(_ key: String, for profile: String, in lines: [String], of project: Project) -> ValueLineLocation? {
    var open: [String] = []
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") {
            open = trimmed.dropFirst().split(separator: ",").map { prefixed($0.trimmingCharacters(in: .whitespaces), with: project.namespace) }
            continue
        }
        guard open.contains(profile), trimmed == key else { continue }
        return ValueLineLocation(index: index, profiles: open)
    }
    return nil
}

private func withKeys(_ lines: [String], _ profiles: [String], _ keys: [String], _ namespace: String?)
    -> [String]
{
    var lines = lines
    let header = profileLine(profiles, in: namespace)
    guard let block = lines.lastIndex(of: header) else { return lines + [header] + keys }
    var end = block + 1
    while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("@") { end += 1 }
    while end > block + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
    lines.insert(contentsOf: keys, at: end)
    return lines
}

func writeKey(_ key: String, profile: String, in project: Project) throws {
    if project.keys(for: profile).contains(key) { return }
    let lines = try fileLines(at: try project.writablePath())
    guard locateKey(key, for: profile, in: lines, of: project) == nil else { return }
    try writeLines(withKeys(lines, [profile], [key], project.namespace), to: try project.writablePath())
}

func writeBlocks(_ blocks: [Block], in project: Project) throws {
    var lines = try fileLines(at: try project.writablePath())
    for block in blocks {
        lines = withKeys(lines, block.profiles, block.keys, project.namespace)
    }
    try writeLines(lines, to: try project.writablePath())
}

func removeKey(_ key: String, profile: String, in project: Project) throws -> Bool {
    var lines = try fileLines(at: try project.writablePath())
    guard let location = locateKey(key, for: profile, in: lines, of: project) else { return false }
    try rejectingSharedBlock(location, key, profile, project)
    lines.remove(at: location.index)
    try writeLines(lines, to: try project.writablePath())
    return true
}

/** Whether the file would give the key up, asked before anything is forgotten. */
func canRemoveKey(_ key: String, profile: String, in project: Project) throws -> Bool {
    let lines = try fileLines(at: try project.writablePath())
    guard let location = locateKey(key, for: profile, in: lines, of: project) else { return false }
    try rejectingSharedBlock(location, key, profile, project)
    return true
}

struct KeyMoveEdit {
    let path: String
    let lines: [String]

    func write() throws {
        try writeLines(lines, to: path)
    }
}

private func removingMovedKey(_ move: KeyMove, from lines: [String], in project: Project) throws -> [String] {
    guard move.source.project?.path == project.path, let profile = move.source.profile else { return lines }
    let location = locateKey(move.sourceKey, for: profile, in: lines, of: project)
        ?? locate(move.sourceKey, for: profile, in: lines, of: project)
    guard let location else { return lines }
    try rejectingSharedBlock(location, move.sourceKey, profile, project)
    var rewritten = lines
    rewritten.remove(at: location.index)
    return rewritten
}

private func addingMovedKey(_ move: KeyMove, value: String?, to lines: [String], in project: Project) -> [String] {
    guard move.target.project?.path == project.path, let profile = move.target.profile,
          project.profiles.contains(profile) else { return lines }
    let entry = value.map { move.targetKey + "=" + $0 } ?? move.targetKey
    return withKeys(lines, [profile], [entry], project.namespace)
}

func prepareKeyMoveEdits(_ move: KeyMove, value: String?) throws -> [KeyMoveEdit] {
    if value != nil, move.target.projectKeys == nil {
        throw StoreFailure.moveRefused("a public value needs a declared target profile in \(projectFileName)")
    }
    var projects: [Project] = []
    for scope in [move.source, move.target] {
        guard let project = scope.project, scope.projectKeys != nil,
              !projects.contains(where: { $0.path == project.path }) else { continue }
        projects.append(project)
    }
    return try projects.map { project in
        let path = try project.writablePath()
        let lines = try fileLines(at: path)
        let removed = try removingMovedKey(move, from: lines, in: project)
        let added = addingMovedKey(move, value: value, to: removed, in: project)
        return KeyMoveEdit(path: path, lines: added)
    }
}
