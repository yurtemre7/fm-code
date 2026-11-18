import Foundation

private func sh(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = args
    p.currentDirectoryURL = dir
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "fmcode-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

/// Creates a git repo, writes and stages the given files.
func makeTempRepo(stage files: [String: String]) throws -> URL {
    let dir = try makeTempDir()
    try sh(["init", "-q"], in: dir)
    try sh(["config", "user.name", "t"], in: dir)
    try sh(["config", "user.email", "t@t"], in: dir)
    try sh(["config", "commit.gpgsign", "false"], in: dir)
    for (path, content) in files {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    if !files.isEmpty { try sh(["add", "-A"], in: dir) }
    return dir
}

/// Writes an executable fake `rtk` script; returns its directory.
func makeFakeRTK(script: String) throws -> URL {
    let dir = try makeTempDir()
    let url = dir.appending(path: "rtk")
    try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return dir
}
