import Foundation

struct UntrackedKey: Equatable {
    let profile: String
    let key: String

    var storedName: String { profile + "/" + key }
}

func untrackedKeys(in project: Project, stored: [String]) -> [UntrackedKey] {
    let profiles = Set(project.profiles)
    let tracked = Set(project.profiles.flatMap { profile in
        (project.keys(for: profile) + project.values(for: profile).map(\.key)).map { profile + "/" + $0 }
    })
    return stored.compactMap { name in
        guard let slash = name.firstIndex(of: "/") else { return nil }
        let profile = String(name[..<slash])
        let key = String(name[name.index(after: slash)...])
        let isIncluded = project.namespace.map { profile.hasPrefix($0 + ".") } ?? profiles.contains(profile)
        guard isIncluded, !tracked.contains(name) else { return nil }
        return UntrackedKey(profile: profile, key: key)
    }.sorted { $0.storedName < $1.storedName }
}

func removeUntrackedKeys(_ keys: [UntrackedKey], store: any SecretStore) throws {
    var removed: [String] = []
    for key in keys {
        do {
            try store.remove(forName: key.storedName)
            removed.append(key.storedName)
        } catch {
            throw StoreFailure.forgetRefused("stopped at \(key.storedName): \(error); removed: \(removed.isEmpty ? "none" : removed.joined(separator: ", ")); the rest are still remembered")
        }
        printToStandardError(messageStyle("forgot", .good) + " " + messageStyle(key.storedName, .bold))
    }
}

func runForgetUntracked(_ arguments: [String]) throws {
    let form = "monkeys forget [@profile] --all --untracked"
    guard arguments.filter({ $0 == "--all" }).count == 1,
          arguments.filter({ $0 == "--untracked" }).count == 1 else {
        throw StoreFailure.badInvocation(form)
    }
    let positional = arguments.filter { $0 != "--all" && $0 != "--untracked" }
    guard positional.isEmpty || (positional.count == 1 && positional[0].hasPrefix("@") && positional[0] != "@") else {
        throw StoreFailure.badInvocation(form)
    }
    guard let project = try locateProject() else {
        throw StoreFailure.badInvocation("\(form) next to a \(projectFileName) file")
    }
    let profile = positional.isEmpty ? nil : try resolveScope(positional).scope.profile
    let keys = untrackedKeys(in: project, stored: try secretStore.storedKeys())
        .filter { profile == nil || $0.profile == profile }
    guard !keys.isEmpty else {
        printToStandardError("nothing untracked")
        return
    }
    let listed = keys.map(\.storedName).joined(separator: ", ")
    try confirmedForget("forget \(keys.count) untracked secret\(keys.count == 1 ? "" : "s"): \(listed)")
    try removeUntrackedKeys(keys, store: secretStore)
}
