import Foundation

let serviceName = "monkeys"

enum StoreFailure: Error {
    case keyNotStored(String)
    case invalidKey(String)
    case emptySecret
    case badInvocation(String)
    case invalidProfileName(String)
    case badProjectFile(String, String)
    case projectFileBorrowed(String)
    case profileNotDeclared(String, [String], String)
    case profileAmbiguous(String, [String])
    case keysNotStored([String], String)
    case namesAlreadyListed([String], String, String)
    case emptyValue
    case keyIsValue(String, String)
    case keyIsSecret(String, String)
    case valuesNeedProject
    case moveRefused(String)
    case forgetRefused(String)
    case badDotenvLine(String, String)
    case bundleFailed(String)
    case backendUnavailable(String)
    case backendFailed(String)
}

extension StoreFailure: CustomStringConvertible {
    var description: String {
        switch self {
        case .keyNotStored(let name):
            return "\(name) is not stored"
        case .invalidKey(let name):
            return "\(name) is not a valid key (an environment variable name)"
        case .emptySecret:
            return "no secret was given"
        case .badInvocation(let form):
            return "expected \(form)"
        case .invalidProfileName(let argument):
            return "\(argument) is not a profile: letters, digits, _ - after the @, with a dot between parts"
        case .badProjectFile(let path, let problem):
            return "\(path): \(problem)"
        case .projectFileBorrowed(let reference):
            return "this checkout has no \(projectFileName), so its keys are read from \(reference); change the file there"
        case .profileNotDeclared(let name, let declared, let path):
            let listed = declared.map { "@" + $0 }.joined(separator: ", ")
            return "@\(name) is not declared in \(path), which declares \(listed)"
        case .profileAmbiguous(let name, let candidates):
            let listed = candidates.map { "@" + $0 }.joined(separator: ", ")
            return "@\(name) could be \(listed); say enough to tell them apart"
        case .keysNotStored(let keys, let profileArgument):
            let subject = keys.count == 1 ? "the secret" : "the secrets"
            let asks = keys.map { "  monkeys remember \(profileArgument)\($0)" }.joined(separator: "\n")
            let place = profileArgument.isEmpty ? "" : " in \(profileArgument.trimmingCharacters(in: .whitespaces))"
            return """
            \(keys.joined(separator: ", ")) \(keys.count == 1 ? "is" : "are") not remembered yet\(place)
            nothing happened. a human types \(subject) into:
            \(asks)
            then try again.
            """
        case .namesAlreadyListed(let keys, let profile, let path):
            return """
            \(path) already lists \(keys.joined(separator: ", ")) for @\(profile)
            inside a project, run takes only the command: monkeys run <command>
            """
        case .emptyValue:
            return "no value was given"
        case .keyIsValue(let key, let profile):
            return "\(key) is a value in \(projectFileName) for @\(profile); replace it with monkeys remember --public \(key), or forget it first"
        case .keyIsSecret(let key, let profile):
            return "\(key) is a key in \(projectFileName) for @\(profile), with its secret in the vault; remove it first"
        case .valuesNeedProject:
            return "a value has nowhere to go without a project: run this next to a \(projectFileName) file"
        case .moveRefused(let reason):
            return reason
        case .forgetRefused(let reason):
            return reason
        case .badDotenvLine(let place, let problem):
            return "\(place): \(problem); nothing was written"
        case .bundleFailed(let reason):
            return reason
        case .backendUnavailable(let reason):
            return reason
        case .backendFailed(let reason):
            return reason
        }
    }
}

protocol SecretStore: Sendable {
    func store(_ value: String, forName name: String) throws
    func read(forName name: String) throws -> String
    func remove(forName name: String) throws
    func storedKeys() throws -> [String]
}

#if os(macOS)
let secretStore: SecretStore = KeychainStore()
#elseif os(Linux)
let secretStore: SecretStore = SecretServiceStore()
#else
#error("monkeys has no secret store for this platform")
#endif

func isValidKey(_ name: String) -> Bool {
    guard let first = name.first, first.isASCII else { return false }
    guard first.isLetter || first == "_" else { return false }
    return name.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }
}
