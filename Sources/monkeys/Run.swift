import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let runInvocation = "monkeys run [@profile] <KEY[,KEY...]> <command>, monkeys run [@profile] --all <command>, or monkeys run [@profile] <command> next to a \(projectFileName) file"

private struct Spending {
    let keys: [String]
    let command: [String]
    let isListedByTheProject: Bool
}

private func namesToSpend(_ scope: Scope, _ arguments: [String]) throws -> Spending {
    if arguments.first == "--all" {
        return Spending(keys: try storedKeysInScope(scope), command: Array(arguments.dropFirst()), isListedByTheProject: false)
    }
    if let keys = scope.projectKeys {
        try rejectListedNames(arguments.first, keys, scope)
        return Spending(keys: keys, command: arguments, isListedByTheProject: true)
    }
    guard let list = arguments.first else { throw StoreFailure.badInvocation(runInvocation) }
    let keys = list.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    return Spending(keys: keys, command: Array(arguments.dropFirst()), isListedByTheProject: false)
}

private func rejectListedNames(_ first: String?, _ listed: [String], _ scope: Scope) throws {
    guard let first, let project = scope.project else { return }
    let given = first.split(separator: ",").map(String.init)
    guard !given.isEmpty, given.allSatisfy(listed.contains) else { return }
    throw StoreFailure.namesAlreadyListed(given, scope.profile ?? "", abbreviatingHome(project.path))
}

func runCommandWithSecrets(_ arguments: [String]) throws -> Never {
    let (scope, rest) = try resolveScope(arguments)
    let spending = try namesToSpend(scope, rest)
    guard !spending.command.isEmpty else { throw StoreFailure.badInvocation(runInvocation) }
    let publicValues = spentValues(of: scope.project, for: scope.profile)

    var values: [SpentValue] = []
    var missing: [String] = []
    for name in spending.keys {
        guard isValidKey(name) else { throw StoreFailure.invalidKey(name) }
        do {
            values.append(SpentValue(name: name, value: try secretStore.read(forName: scope.storedName(name))))
        } catch StoreFailure.keyNotStored {
            missing.append(name)
        }
    }
    guard missing.isEmpty || spending.isListedByTheProject else { throw StoreFailure.keysNotStored(missing, scope.profileArgument) }
    if !missing.isEmpty { warnOfRunningWithout(missing, scope.profileArgument) }
    for entry in publicValues { setenv(entry.name, entry.value, 1) }
    let status = runRedacted(spending.command, values)
    restoreTerminal()
    if status != 0 && !missing.isEmpty { askForWhatTheFailedRunLacked(missing, scope.profileArgument) }
    exitLike(status)
}

private func placeOfProfile(_ profileArgument: String) -> String {
    profileArgument.isEmpty ? "" : " in \(profileArgument.trimmingCharacters(in: .whitespaces))"
}

private func pronoun(for keys: [String]) -> String {
    keys.count == 1 ? "it" : "them"
}

private func warnOfRunningWithout(_ keys: [String], _ profileArgument: String) {
    let verb = keys.count == 1 ? "is" : "are"
    let warning = "\(keys.joined(separator: ", ")) \(verb) not remembered yet\(placeOfProfile(profileArgument)); the command runs without \(pronoun(for: keys))"
    printToStandardError(messageStyle("monkeys:", .brand) + " " + warning)
}

private func askForWhatTheFailedRunLacked(_ keys: [String], _ profileArgument: String) {
    let subject = keys.count == 1 ? "the secret" : "the secrets"
    let asks = keys.map { "  monkeys remember \(profileArgument)\($0)" }.joined(separator: "\n")
    printToStandardError(messageStyle("monkeys:", .bad) + """
         the command failed without \(keys.joined(separator: ", ")). if it needs \(pronoun(for: keys)), a human types \(subject) into:
        \(asks)
        then try again.
        """)
}
