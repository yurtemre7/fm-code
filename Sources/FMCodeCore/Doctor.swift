import Foundation

public enum CheckStatus: Sendable {
    case ok, warn, fail
    var symbol: String {
        switch self { case .ok: "[✓]"; case .warn: "[!]"; case .fail: "[✗]" }
    }
}

public struct Check: Equatable, Sendable {
    public var status: CheckStatus
    public var title: String
    public var detail: String?
}

public enum RepoState: Equatable, Sendable {
    case notARepo, nothingStaged, staged(files: Int, hookInstalled: Bool)
}

public struct DoctorInputs: Sendable {
    public var macOS: OperatingSystemVersion
    public var isAppleSilicon: Bool
    public var model: ModelState
    public var gitVersion: String?
    public var rtkVersion: String?
    public var repo: RepoState

    public static func gather(cwd: URL, env: [String: String] = ProcessInfo.processInfo.environment) -> DoctorInputs {
        DoctorInputs(
            macOS: ProcessInfo.processInfo.operatingSystemVersion,
            isAppleSilicon: appleSilicon(),
            model: .current,
            gitVersion: version(of: Git.executable, prefix: "git version "),
            rtkVersion: findRTK(env: env).flatMap { version(of: $0, prefix: "rtk ") },
            repo: repoState(cwd)
        )
    }
}

private func appleSilicon() -> Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
}

/// `git version 2.50.1 (Apple Git-155)` → `2.50.1`
private func version(of exe: URL, prefix: String) -> String? {
    guard let r = try? runProcess(exe, ["--version"]), r.status == 0 else { return nil }
    let line = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let rest = line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
    return rest.split(separator: " ").first.map(String.init)
}

private func repoState(_ cwd: URL) -> RepoState {
    guard Git.succeeds(["rev-parse", "--is-inside-work-tree"], in: cwd) else { return .notARepo }
    let files = (try? Git.run(["diff", "--staged", "--name-only"], in: cwd))?
        .split(separator: "\n").count ?? 0
    if files == 0 { return .nothingStaged }
    let hooks = (try? Git.run(["rev-parse", "--path-format=absolute", "--git-path", "hooks"], in: cwd))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hook = (try? String(contentsOfFile: hooks + "/prepare-commit-msg", encoding: .utf8)) ?? ""
    return .staged(files: files, hookInstalled: hook.contains("fm-code"))
}

public func checks(_ i: DoctorInputs) -> [Check] {
    var out: [Check] = []
    let v = i.macOS
    let os = "macOS \(v.majorVersion).\(v.minorVersion)"
    switch (v.majorVersion >= 26, i.isAppleSilicon) {
    case (true, true): out.append(Check(status: .ok, title: "\(os) on Apple Silicon"))
    case (false, _): out.append(Check(status: .fail, title: os, detail: "macOS 26 or later is required"))
    case (_, false): out.append(Check(status: .fail, title: "\(os) on Intel", detail: "Apple Silicon is required"))
    }

    out.append(i.model == .available
        ? Check(status: .ok, title: "On-device model available")
        : Check(status: .fail, title: "On-device model unavailable", detail: i.model.explanation))

    out.append(i.gitVersion.map { Check(status: .ok, title: "git \($0) (\(Git.executable.path))") }
        ?? Check(status: .fail, title: "git not found", detail: "install Xcode Command Line Tools: xcode-select --install"))

    out.append(i.rtkVersion.map { Check(status: .ok, title: "rtk \($0) — compact git output enabled") }
        ?? Check(status: .warn, title: "rtk not found", detail: "optional — install it for more compact git output (or FM_CODE_NO_RTK=1 is set)"))

    switch i.repo {
    case .notARepo:
        out.append(Check(status: .warn, title: "Not inside a git repository", detail: "run fm-code from a repo"))
    case .nothingStaged:
        out.append(Check(status: .warn, title: "Inside a git repo, nothing staged", detail: "stage changes with `git add`"))
    case .staged(let n, let hook):
        out.append(Check(status: .ok, title: "Inside a git repo, \(n) file\(n == 1 ? "" : "s") staged"))
        out.append(hook
            ? Check(status: .ok, title: "prepare-commit-msg hook installed")
            : Check(status: .warn, title: "prepare-commit-msg hook not installed", detail: "optional — run `fm-code --hook`"))
    }
    return out
}

public func renderDoctor(_ checks: [Check]) -> String {
    var s = "fm-code doctor\n"
    for c in checks {
        s += "\(c.status.symbol) \(c.title)"
        if let d = c.detail { s += " — \(d)" }
        s += "\n"
    }
    let commands = ReadOnlyGitCommand.allCases.map { "`git \($0.args.joined(separator: " "))`" }.joined(separator: ", ")
    s += """

        What the model can do: run read-only \(commands).
        It never changes your repo; only `fm-code -c` commits, after you confirm.


        """
    let issues = checks.filter { $0.status == .fail }.count
    s += issues == 0
        ? "No issues found!\n"
        : "\(issues) issue\(issues == 1 ? "" : "s") — fm-code can't run until fixed\n"
    return s
}
