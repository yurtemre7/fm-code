import Foundation

private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// prepare-commit-msg hook. Only fills in a message for a plain `git commit`
/// ($2 empty); any failure leaves git's message file untouched.
public func hookScript(fallback: String) -> String {
    """
    #!/bin/sh
    # Installed by fm-code: prefills the commit message.
    [ -n "$2" ] && exit 0
    FM=\(shellQuote(fallback))
    [ -x "$FM" ] || FM=fm-code
    msg=$("$FM" 2>/dev/null) || exit 0
    [ -n "$msg" ] || exit 0
    { printf '%s\\n' "$msg"; cat "$1"; } > "$1.fm-code" && mv "$1.fm-code" "$1"
    exit 0

    """
}

/// Installs the hook where git looks for hooks (honours core.hooksPath).
@discardableResult
public func installHook(in dir: URL, fallback: String) throws -> URL {
    guard Git.succeeds(["rev-parse", "--is-inside-work-tree"], in: dir) else { throw CLIError.notARepo }
    let hooksPath = try Git.run(["rev-parse", "--path-format=absolute", "--git-path", "hooks"], in: dir)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let hooks = URL(fileURLWithPath: hooksPath)
    let hook = hooks.appending(path: "prepare-commit-msg")
    let fm = FileManager.default
    if fm.fileExists(atPath: hook.path) { throw CLIError.hookExists(hook.path) }
    try fm.createDirectory(at: hooks, withIntermediateDirectories: true)
    try hookScript(fallback: fallback).write(to: hook, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    return hook
}
