import Foundation
import Testing
@testable import FMCodeCore

struct Unexpected: Error {}

@Test func finalizeUsesFirstWhenShort() async throws {
    var retried = false
    let r = try await finalize(
        draft: { .init(type: .fix, subject: "ok", breaking: false) },
        retry: { _ in retried = true; throw Unexpected() })
    #expect(r == "fix: ok")
    #expect(!retried)
}

@Test func finalizeRetriesOnceThenFits() async throws {
    var calls = 0
    var reportedLength = 0
    let long = String(repeating: "a ", count: 50)
    let r = try await finalize(
        draft: { .init(type: .feat, subject: long, breaking: false) },
        retry: { n in calls += 1; reportedLength = n; return .init(type: .feat, subject: long, breaking: false) })
    #expect(calls == 1)
    #expect(reportedLength > 72)
    #expect(r.count <= 72)
}

@Test func finalizeUsesShorterRetry() async throws {
    let long = String(repeating: "a ", count: 50)
    let r = try await finalize(
        draft: { .init(type: .feat, subject: long, breaking: false) },
        retry: { _ in .init(type: .feat, subject: "short one", breaking: false) })
    #expect(r == "feat: short one")
}

@Test func unknownTypeMapsToChore() {
    let m = CommitMessage(type: "wat", subject: "do it", breaking: false)
    #expect(m.draft == CommitDraft(type: .chore, subject: "do it", breaking: false))
}

@Test func knownTypeMaps() {
    #expect(CommitMessage(type: "perf", subject: "s", breaking: true).draft.type == .perf)
}

@Test func gitToolRefusesUnknownCommand() async throws {
    let repo = try makeTempRepo(stage: ["a.txt": "x\n"])
    let tool = GitTool(cwd: repo, runner: ToolGitRunner(rtk: nil))
    #expect(try await tool.run(command: "push") == "refused: not allowed")
    #expect(try await tool.run(command: "status").contains("a.txt"))
}

@Test func gitToolSurvivesRepoWithoutCommits() async throws {
    let repo = try makeTempRepo(stage: [:])
    let tool = GitTool(cwd: repo, runner: ToolGitRunner(rtk: nil))
    #expect(try await tool.run(command: "log").hasPrefix("git error:"))
}

@Test func gitToolRepeatCallIsNotResent() async throws {
    let repo = try makeTempRepo(stage: ["a.txt": "hello\n"])
    let tool = GitTool(cwd: repo, runner: ToolGitRunner(rtk: nil))
    #expect(try await tool.run(command: "diff").contains("+hello"))
    #expect(try await tool.run(command: "diff") == "(already shown above)")
}

@Test func gitToolEnforcesTotalBudget() async throws {
    let repo = try makeTempRepo(stage: ["big.txt": String(repeating: "line\n", count: 5_000)])
    let tool = GitTool(cwd: repo, runner: ToolGitRunner(rtk: nil), budget: 100)
    let first = try await tool.run(command: "diff")
    #expect(first.count <= 100 + "\n[truncated]".count)
    #expect(try await tool.run(command: "status") == "(output budget used up — write the message now)")
}

@Test func finalizeRetriesEmptySubject() async throws {
    let r = try await finalize(
        draft: { .init(type: .feat, subject: "  ", breaking: false) },
        retry: { _ in .init(type: .feat, subject: "add y", breaking: false) })
    #expect(r == "feat: add y")
}

@Test func finalizeKeepsFirstDraftWhenRetryFails() async throws {
    let long = String(repeating: "word ", count: 20)
    let r = try await finalize(
        draft: { .init(type: .feat, subject: long, breaking: false) },
        retry: { _ in throw Unexpected() })
    #expect(r.hasPrefix("feat: word"))
    #expect(r.count <= 72)
}
