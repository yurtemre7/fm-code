import Foundation

public let defaultRepoURL = "https://github.com/yurtemre7/fm-code.git"

public enum UpdateResult: Equatable, Sendable {
    case upToDate(String)
    case updated(from: String?, to: String)
}

public enum UpdateError: Error, Equatable, CustomStringConvertible {
    case installFailed(Int32)
    public var description: String {
        switch self { case .installFailed(let code): "install.sh failed (exit \(code))" }
    }
}

/// Where `fm-code update` keeps its source clone and the last installed commit.
public func updateCache() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return caches.appending(path: "fm-code")
}

/// Brings a shallow clone of `repo`'s `main` in `cache/src` up to date, then calls `install`
/// with that folder unless its commit is the one last installed to `target` (or `force` is set).
public func update(
    cache: URL, repo: String, target: URL, force: Bool = false, install: (URL) throws -> Void
) throws -> UpdateResult {
    let src = cache.appending(path: "src")
    // One stamp per install folder, so installing elsewhere doesn't mark this one current.
    let key = target.standardizedFileURL.path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
    let stamp = cache.appending(path: "installed-\(key)")
    if FileManager.default.fileExists(atPath: src.appending(path: ".git").path) {
        try Git.run(["fetch", "-q", "--depth", "1", repo, "main"], in: src)
        try Git.run(["reset", "-q", "--hard", "FETCH_HEAD"], in: src)
    } else {
        try? FileManager.default.removeItem(at: src)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Git.run(["clone", "-q", "--depth", "1", "--branch", "main", repo, src.path])
    }
    let head = try Git.run(["rev-parse", "--short", "HEAD"], in: src).trimmingCharacters(in: .whitespacesAndNewlines)
    let previous = (try? String(contentsOf: stamp, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    if previous == head && !force { return .upToDate(head) }
    try install(src)
    try head.write(to: stamp, atomically: true, encoding: .utf8)
    return .updated(from: previous, to: head)
}

/// Runs `src/install.sh` with the terminal attached, installing into `dir`.
/// Uses posix_spawn, not Process: Process puts the child in its own process group, which
/// keeps it out of the terminal's foreground group, so `sudo` can't hide the password it reads.
public func runInstallScript(in src: URL, to dir: URL) throws {
    let args = ["/bin/sh", src.appending(path: "install.sh").path]
    let env = ProcessInfo.processInfo.environment.merging(["INSTALL_DIR": dir.path]) { $1 }.map { "\($0)=\($1)" }
    let argv = args.map { strdup($0) } + [nil]
    let envp = env.map { strdup($0) } + [nil]
    defer { (argv + envp).forEach { free($0) } }

    var pid = pid_t()
    let err = posix_spawn(&pid, args[0], nil, nil, argv, envp)
    guard err == 0 else { throw UpdateError.installFailed(Int32(err)) }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    // Exit code if it exited normally (WEXITSTATUS); 128 + signal if it was killed.
    let code = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + status & 0x7f
    guard code == 0 else { throw UpdateError.installFailed(code) }
}
