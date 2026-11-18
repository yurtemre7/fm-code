import Foundation
import Testing
@testable import FMCodeCore

@Test func argsAreExact() {
    #expect(ReadOnlyGitCommand.diff.args == ["diff", "--staged"])
    #expect(ReadOnlyGitCommand.diffStat.args == ["diff", "--staged", "--stat"])
    #expect(ReadOnlyGitCommand.status.args == ["status", "--short"])
    #expect(ReadOnlyGitCommand.log.args == ["log", "--oneline", "-n", "10"])
}

@Test func stagedDiffVisible() throws {
    let repo = try makeTempRepo(stage: ["a.txt": "hello\n"])
    #expect(try Git.run(ReadOnlyGitCommand.diff.args, in: repo).contains("+hello"))
}

@Test func failureThrows() {
    #expect(throws: GitError.self) { try Git.run(["not-a-command"]) }
}

@Test func truncates() {
    let t = truncate(String(repeating: "x", count: 10_000))
    #expect(t.count <= 6000 + "\n[truncated]".count)
    #expect(t.hasSuffix("[truncated]"))
    #expect(truncate("short") == "short")
}

@Test func largeDiffDoesNotHang() throws {
    let repo = try makeTempRepo(stage: ["big.txt": String(repeating: "line\n", count: 200_000)])
    #expect(try Git.run(ReadOnlyGitCommand.diff.args, in: repo).count > 100_000)
}

@Test(.timeLimit(.minutes(1)))
func manyConcurrentRunsDoNotStarve() async throws {
    try await withThrowingTaskGroup(of: Bool.self) { group in
        for _ in 0..<64 { group.addTask { Git.succeeds(["--version"]) } }
        for try await ok in group { #expect(ok) }
    }
}

@Test func binaryDiffDoesNotCrash() throws {
    let repo = try makeTempRepo(stage: [:])
    try Data([0, 1, 2, 255, 254, 0]).write(to: repo.appending(path: "b.bin"))
    _ = try Git.run(["add", "b.bin"], in: repo)
    #expect(try Git.run(ReadOnlyGitCommand.diff.args, in: repo).contains("Binary"))
}

@Test func findRTKHonorsOptOutAndPath() throws {
    let bin = try makeFakeRTK(script: "echo RTK $@")
    #expect(findRTK(env: ["PATH": bin.path])?.lastPathComponent == "rtk")
    #expect(findRTK(env: ["PATH": bin.path, "FM_CODE_NO_RTK": "1"]) == nil)
}

@Test func runnerUsesRTKWhenPresent() throws {
    let repo = try makeTempRepo(stage: ["a.txt": "hello\n"])
    let rtk = try makeFakeRTK(script: "echo RTK $@").appending(path: "rtk")
    #expect(try ToolGitRunner(rtk: rtk).run(.status, in: repo) == "RTK git status --short\n")
}

@Test func runnerFallsBackWhenRTKFails() throws {
    let repo = try makeTempRepo(stage: ["a.txt": "hello\n"])
    let rtk = try makeFakeRTK(script: "exit 3").appending(path: "rtk")
    #expect(try ToolGitRunner(rtk: rtk).run(.diff, in: repo).contains("+hello"))
}

@Test func runnerWithoutRTKUsesGit() throws {
    let repo = try makeTempRepo(stage: ["a.txt": "hello\n"])
    #expect(try ToolGitRunner(rtk: nil).run(.status, in: repo).contains("a.txt"))
}
