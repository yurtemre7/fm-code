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
    var problem = ""
    let long = String(repeating: "a ", count: 50)
    let r = try await finalize(
        draft: { .init(type: .feat, subject: long, breaking: false) },
        retry: { p in calls += 1; problem = p; return .init(type: .feat, subject: long, breaking: false) })
    #expect(calls == 1)
    #expect(problem.contains("chars"))
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

@Test func knownSubjectsFindsCommitLinesInDiffAndLog() {
    let text = """
        -feat(parser): add fenced code block support
        +feat: add fenced code block support
        +see `fix: handle nil widget state` below
        728fc38 feat: drop scopes and match style
        +fix: typo
        +let x = 1
        """
    #expect(knownSubjects(in: text) == [
        "add fenced code block support", "add fenced code block support",
        "handle nil widget state", "drop scopes and match style",
    ])
}

@Test func isCopyCatchesExtendedCopies() {
    let known = ["add fenced code block support"]
    #expect(isCopy("Add fenced code block support to README.md", of: known))
    #expect(isCopy("add fenced code block support", of: known))
    #expect(!isCopy("add fenced code block supporting", of: known))
    #expect(!isCopy("drop scopes from commit messages", of: known))
}

@Test func finalizeRetriesCopiedSubject() async throws {
    var problem = ""
    let r = try await finalize(
        known: ["add fenced code block support"],
        draft: { .init(type: .feat, subject: "add fenced code block support to README.md", breaking: false) },
        retry: { p in problem = p; return .init(type: .refactor, subject: "drop scopes from commit messages", breaking: false) })
    #expect(problem.contains("copied"))
    #expect(r == "refactor: drop scopes from commit messages")
}
