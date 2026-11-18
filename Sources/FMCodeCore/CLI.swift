import Foundation

public enum Command: Equatable, Sendable {
    case print, commit, installHook, doctor, help

    public static func parse(_ args: [String]) -> Command? {
        switch args {
        case []: .print
        case ["-c"], ["--commit"]: .commit
        case ["--hook"]: .installHook
        case ["doctor"]: .doctor
        case ["-h"], ["--help"]: .help
        default: nil
        }
    }
}

public let doctorHint = "Run 'fm-code doctor' to check your setup."

public let usage = """
    fm-code — one-line Conventional Commit messages from your staged changes,
    written by Apple's on-device model.

    Usage:
      fm-code            print a commit message for the staged changes
      fm-code -c         show the message, then commit after you confirm
      fm-code --hook     install a prepare-commit-msg hook (prefills `git commit`)
      fm-code doctor     check your setup and see what's enabled

    Set FM_CODE_NO_RTK=1 to stop using rtk for compact git output.
    \(doctorHint)
    """

public enum CLIError: Error, Equatable, CustomStringConvertible {
    case notARepo, nothingStaged, hookExists(String)

    public var description: String {
        switch self {
        case .notARepo: "not a git repository"
        case .nothingStaged: "nothing staged — stage changes with `git add` first"
        case .hookExists(let path): "a prepare-commit-msg hook already exists at \(path) — not overwriting"
        }
    }
}

public func preflight(in dir: URL) throws {
    guard Git.succeeds(["rev-parse", "--is-inside-work-tree"], in: dir) else { throw CLIError.notARepo }
    if Git.succeeds(["diff", "--staged", "--quiet"], in: dir) { throw CLIError.nothingStaged }
}
