import Foundation
import Testing
@testable import FMCodeCore

struct Unexpected: Error {}

@Test func finalizeUsesFirstWhenShort() async throws {
    var retried = false
    let r = try await finalize(
        draft: { .init(type: .fix, scope: nil, subject: "ok", breaking: false) },
        retry: { _ in retried = true; throw Unexpected() })
    #expect(r == "fix: ok")
    #expect(!retried)
}

@Test func finalizeRetriesOnceThenFits() async throws {
    var calls = 0
    var reportedLength = 0
    let long = String(repeating: "a ", count: 50)
    let r = try await finalize(
        draft: { .init(type: .feat, scope: "x", subject: long, breaking: false) },
        retry: { n in calls += 1; reportedLength = n; return .init(type: .feat, scope: "x", subject: long, breaking: false) })
    #expect(calls == 1)
    #expect(reportedLength > 72)
    #expect(r.count <= 72)
}

@Test func finalizeUsesShorterRetry() async throws {
    let long = String(repeating: "a ", count: 50)
    let r = try await finalize(
        draft: { .init(type: .feat, scope: nil, subject: long, breaking: false) },
        retry: { _ in .init(type: .feat, scope: "ui", subject: "short one", breaking: false) })
    #expect(r == "feat(ui): short one")
}

@Test func unknownTypeMapsToChore() {
    let m = CommitMessage(type: "wat", scope: "core", subject: "do it", breaking: false)
    #expect(m.draft == CommitDraft(type: .chore, scope: "core", subject: "do it", breaking: false))
}

@Test func knownTypeMaps() {
    #expect(CommitMessage(type: "perf", scope: nil, subject: "s", breaking: true).draft.type == .perf)
}

@Test func gitToolRefusesUnknownCommand() async throws {
    let repo = try makeTempRepo(stage: ["a.txt": "x\n"])
    let tool = GitTool(cwd: repo, runner: ToolGitRunner(rtk: nil))
    #expect(try await tool.run(command: "push") == "refused: not allowed")
    #expect(try await tool.run(command: "status").contains("a.txt"))
}
