import Foundation

struct KeyMove {
    let source: Scope
    let sourceKey: String
    let target: Scope
    let targetKey: String
}

func parseKeyMove(_ arguments: [String]) throws -> KeyMove {
    let (source, remaining) = try resolveScope(arguments)
    guard let sourceKey = remaining.first, remaining.count > 1 else {
        throw StoreFailure.badInvocation(moveForm)
    }
    _ = try requireKey([sourceKey])
    let destination = Array(remaining.dropFirst())
    let hasTargetProfile = destination[0].hasPrefix("@")
    let (target, names) = hasTargetProfile ? try resolveScope(destination) : (source, destination)
    let targetKey = try requireKey(names.isEmpty ? [sourceKey] : names)
    return KeyMove(source: source, sourceKey: sourceKey, target: target, targetKey: targetKey)
}

private func validateKeyMove(_ move: KeyMove, stored: [String]) throws {
    let sourceName = move.source.storedName(move.sourceKey)
    let targetName = move.target.storedName(move.targetKey)
    guard sourceName != targetName else {
        throw StoreFailure.moveRefused("\(sourceName) is already its name")
    }
    let targetKeys = move.target.projectKeys ?? []
    let targetValue = move.target.project.flatMap { project in
        move.target.profile.flatMap { project.value(of: move.targetKey, for: $0) }
    }
    guard !stored.contains(targetName), !targetKeys.contains(move.targetKey), targetValue == nil else {
        throw StoreFailure.moveRefused("\(targetName) already exists; a move never replaces a key or value")
    }
}

private func transferSecret(from source: String, to target: String, store: any SecretStore) throws {
    let secret = try store.read(forName: source)
    try store.store(secret, forName: target)
    do {
        try store.remove(forName: source)
    } catch {
        throw StoreFailure.moveRefused("stored \(target), but could not remove \(source): \(error); \(projectFileName) declarations were not changed")
    }
}

func moveKey(_ move: KeyMove, store: any SecretStore) throws {
    let stored = try store.storedKeys()
    try validateKeyMove(move, stored: stored)
    let sourceName = move.source.storedName(move.sourceKey)
    let targetName = move.target.storedName(move.targetKey)
    let hasSecret = stored.contains(sourceName)
    let hasDeclaration = move.source.projectKeys?.contains(move.sourceKey) ?? false
    let value = move.source.project.flatMap { project in
        move.source.profile.flatMap { project.value(of: move.sourceKey, for: $0) }
    }
    guard hasSecret || hasDeclaration || value != nil else {
        throw StoreFailure.keyNotStored(sourceName)
    }
    let edits = try prepareKeyMoveEdits(move, value: value)
    if hasSecret {
        try transferSecret(from: sourceName, to: targetName, store: store)
    }
    for edit in edits { try edit.write() }
    printToStandardError(messageStyle("moved", .good) + " \(sourceName) to \(targetName)")
}

func runMove(_ arguments: [String]) throws {
    if arguments.count == 2 {
        let (source, target) = (arguments[0], arguments[1])
        if source.hasPrefix("+"), target.hasPrefix("+") {
            return try moveNamespace(source, target)
        }
        if source.hasPrefix("@"), target.hasPrefix("@") {
            guard source != "@", target != "@" else {
                throw StoreFailure.badInvocation(moveForm)
            }
            return try moveProfile(source, target)
        }
    }
    try moveKey(parseKeyMove(arguments), store: secretStore)
}
