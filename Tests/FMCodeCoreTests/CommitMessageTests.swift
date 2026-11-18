import Testing
@testable import FMCodeCore

@Test func rendersBreakingWithoutScope() {
    #expect(render(.init(type: .feat, subject: "add refresh", breaking: true)) == "feat!: add refresh")
    #expect(render(.init(type: .fix, subject: "x", breaking: false)) == "fix: x")
}

@Test func sanitizesSubject() {
    #expect(render(.init(type: .docs, subject: "Update README.\nmore", breaking: false)) == "docs: update README")
}

@Test func sanitizesWhitespace() {
    #expect(render(.init(type: .fix, subject: "  fix   the\tbug  ", breaking: false)) == "fix: fix the bug")
}

@Test func fitTrims() {
    let long = String(repeating: "word ", count: 20)
    let s = fit(.init(type: .refactor, subject: long, breaking: false))
    #expect(s.count <= 72)
    #expect(s.hasPrefix("refactor: "))
    #expect(!s.hasSuffix(" "))
}

@Test func fitKeepsShortMessage() {
    #expect(fit(.init(type: .chore, subject: "bump x", breaking: false)) == "chore: bump x")
}

@Test func allElevenTypes() {
    #expect(CommitType.allCases.map(\.rawValue) == ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"])
}

@Test func keepsLeadingAcronym() {
    #expect(render(.init(type: .docs, subject: "README updates", breaking: false)) == "docs: README updates")
    #expect(render(.init(type: .feat, subject: "API client retries", breaking: false)) == "feat: API client retries")
    #expect(render(.init(type: .feat, subject: "Add parser", breaking: false)) == "feat: add parser")
}

@Test func stripsRepeatedTypePrefix() {
    #expect(render(.init(type: .feat, subject: "feat: add parser", breaking: false)) == "feat: add parser")
    #expect(render(.init(type: .fix, subject: "Fix(ui)!: handle nil", breaking: false)) == "fix: handle nil")
}

@Test func skipsBlankFirstLine() {
    #expect(render(.init(type: .feat, subject: "   \nadd y", breaking: false)) == "feat: add y")
}
