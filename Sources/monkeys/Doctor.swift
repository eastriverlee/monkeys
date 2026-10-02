struct DoctorReport {
    let lines: [String]
    let hasMissingKeys: Bool
}

private func storedMark(_ isStored: Bool) -> String {
    isStored ? outputStyle("✓", .good) : outputStyle("✗", .bad)
}

private func doctorProfileLines(_ profile: String, project: Project, stored: Set<String>, untracked: [UntrackedKey]) -> [String] {
    let label = profile == project.defaultProfile ? outputStyle("  default", .dim) : ""
    let header = outputStyle("@" + project.shortName(profile), .bold) + label
    let keys = project.keys(for: profile).map { key in
        "  " + storedMark(stored.contains(profile + "/" + key)) + " " + key
    }
    let values = project.values(for: profile).map { entry in
        "  " + storedMark(true) + " " + entry.key + outputStyle("=" + entry.value, .dim)
    }
    let extraKeys = untracked.filter { $0.profile == profile }.map { entry in
        "  " + outputStyle("-", .dim) + " " + entry.key
    }
    return [header] + keys + values + extraKeys
}

func doctorReport(in project: Project, stored: [String], isShort: Bool) -> DoctorReport {
    let names = Set(stored)
    let untracked = untrackedKeys(in: project, stored: stored)
    let extraProfiles = Set(untracked.map(\.profile)).subtracting(project.profiles).sorted()
    var lines: [String] = []
    var hasMissingKeys = false
    for profile in project.profiles + extraProfiles {
        let missing = project.keys(for: profile).filter { !names.contains(profile + "/" + $0) }
        hasMissingKeys = hasMissingKeys || !missing.isEmpty
        if isShort {
            if !missing.isEmpty { lines.append("missing @\(project.shortName(profile)): " + missing.joined(separator: ",")) }
            continue
        }
        lines += doctorProfileLines(profile, project: project, stored: names, untracked: untracked)
    }
    return DoctorReport(lines: lines, hasMissingKeys: hasMissingKeys)
}
