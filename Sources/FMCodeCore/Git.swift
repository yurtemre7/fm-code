import Foundation

public enum GitError: Error, CustomStringConvertible {
    case failed(String)
    public var description: String {
        switch self { case .failed(let msg): msg }
    }
}

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

/// Runs an executable with an argv array (no shell). Drains stdout and stderr
/// concurrently before waiting so large outputs can't deadlock. stderr is read on
/// a dedicated Thread, not GCD: callers may block every cooperative-pool thread,
/// which starves GCD's default queue.
func runProcess(_ exe: URL, _ args: [String], in dir: URL? = nil) throws -> ProcessResult {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    if let dir { p.currentDirectoryURL = dir }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    p.standardInput = FileHandle.nullDevice
    try p.run()

    nonisolated(unsafe) var errData = Data()
    let done = DispatchSemaphore(value: 0)
    Thread {
        errData = err.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }.start()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    done.wait()
    p.waitUntilExit()
    return ProcessResult(
        status: p.terminationStatus,
        stdout: String(decoding: outData, as: UTF8.self),
        stderr: String(decoding: errData, as: UTF8.self)
    )
}

public enum Git {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    @discardableResult
    public static func run(_ args: [String], in dir: URL? = nil) throws -> String {
        let r = try runProcess(executable, args, in: dir)
        guard r.status == 0 else {
            throw GitError.failed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return r.stdout
    }

    /// True when the git command exits 0.
    public static func succeeds(_ args: [String], in dir: URL? = nil) -> Bool {
        (try? runProcess(executable, args, in: dir).status) == 0
    }
}

public enum ReadOnlyGitCommand: String, CaseIterable, Sendable {
    case diff, diffStat, status, log

    public var args: [String] {
        switch self {
        case .diff: ["diff", "--staged"]
        case .diffStat: ["diff", "--staged", "--stat"]
        case .status: ["status", "--short"]
        case .log: ["log", "--oneline", "-n", "10"]
        }
    }
}

public func truncate(_ s: String, limit: Int = 6000) -> String {
    guard s.count > limit else { return s }
    return String(s.prefix(limit)) + "\n[truncated]"
}

public func findRTK(env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
    if env["FM_CODE_NO_RTK"] == "1" { return nil }
    let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
    for dir in dirs where !dir.isEmpty {
        let path = (dir as NSString).appendingPathComponent("rtk")
        if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
    }
    return nil
}

/// Runs the model's allowlisted git commands, via `rtk git` when available.
public struct ToolGitRunner: Sendable {
    public let rtk: URL?

    public init(rtk: URL?) { self.rtk = rtk }

    public func run(_ cmd: ReadOnlyGitCommand, in dir: URL) throws -> String {
        if let rtk, let r = try? runProcess(rtk, ["git"] + cmd.args, in: dir), r.status == 0 {
            return r.stdout
        }
        return try Git.run(cmd.args, in: dir)
    }
}
