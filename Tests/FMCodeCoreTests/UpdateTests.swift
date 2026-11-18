import Foundation
import Testing
@testable import FMCodeCore

/// A local "upstream" repo with one commit on `main`.
private func makeUpstream() throws -> URL {
    let repo = try makeTempRepo(stage: ["install.sh": "echo v1\n"])
    try Git.run(["checkout", "-q", "-B", "main"], in: repo)
    try Git.run(["commit", "-q", "-m", "v1"], in: repo)
    return repo
}

@Test func updateClonesInstallsThenSkipsWhenCurrent() throws {
    let upstream = try makeUpstream()
    let cache = try makeTempDir().appending(path: "cache")
    var installed: [String] = []
    let install: (URL) throws -> Void = { installed.append(try String(contentsOf: $0.appending(path: "install.sh"), encoding: .utf8)) }

    guard case .updated(nil, let v1) = try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), install: install) else {
        Issue.record("expected first install"); return
    }
    #expect(installed == ["echo v1\n"])
    #expect(try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), install: install) == .upToDate(v1))
    #expect(installed.count == 1)

    try "echo v2\n".write(to: upstream.appending(path: "install.sh"), atomically: true, encoding: .utf8)
    try Git.run(["commit", "-q", "-am", "v2"], in: upstream)
    guard case .updated(v1, _) = try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), install: install) else {
        Issue.record("expected update from v1"); return
    }
    #expect(installed.last == "echo v2\n")
}

@Test func updateForceReinstallsAndFailedInstallIsRetried() throws {
    let upstream = try makeUpstream()
    let cache = try makeTempDir().appending(path: "cache")
    #expect(throws: UpdateError.installFailed(1)) {
        try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), install: { _ in throw UpdateError.installFailed(1) })
    }
    var calls = 0
    _ = try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), install: { _ in calls += 1 })
    _ = try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: "/opt/a"), force: true, install: { _ in calls += 1 })
    #expect(calls == 2)
}

@Test func installScriptGetsInstallDir() throws {
    let src = try makeTempDir(), out = try makeTempDir()
    try "echo \"$INSTALL_DIR\" > \"$INSTALL_DIR/where\"\n".write(to: src.appending(path: "install.sh"), atomically: true, encoding: .utf8)
    try runInstallScript(in: src, to: out)
    #expect(try String(contentsOf: out.appending(path: "where"), encoding: .utf8) == out.path + "\n")
    try "exit 3\n".write(to: src.appending(path: "install.sh"), atomically: true, encoding: .utf8)
    #expect(throws: UpdateError.installFailed(3)) { try runInstallScript(in: src, to: out) }
}

@Test func updateTracksEachInstallFolderSeparately() throws {
    let upstream = try makeUpstream()
    let cache = try makeTempDir().appending(path: "cache")
    var calls = 0
    for dir in ["/opt/a", "/opt/b", "/opt/a"] {
        _ = try update(cache: cache, repo: upstream.path, target: URL(fileURLWithPath: dir), install: { _ in calls += 1 })
    }
    #expect(calls == 2)
}

@Test func updateSkipsCommitRecordedByInstallScript() throws {
    let upstream = try makeUpstream()
    let cache = try makeTempDir().appending(path: "cache")
    let target = URL(fileURLWithPath: "/opt/a")
    let head = try Git.run(["rev-parse", "HEAD"], in: upstream).trimmingCharacters(in: .whitespacesAndNewlines)
    // Short hash, as older stamps stored it: still counts as current.
    try recordInstalled(commit: String(head.prefix(7)), cache: cache, target: target)
    var calls = 0
    #expect(try update(cache: cache, repo: upstream.path, target: target, install: { _ in calls += 1 }) == .upToDate(String(head.prefix(7))))
    #expect(calls == 0)
    #expect(installedCommit(cache: cache, target: URL(fileURLWithPath: "/opt/b")) == nil)
}
