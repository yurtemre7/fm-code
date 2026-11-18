import Testing
@testable import FMCodeCore

@Test func rendersScopeAndBreaking() {
    #expect(render(.init(type: .feat, scope: "auth", subject: "add refresh", breaking: true)) == "feat(auth)!: add refresh")
}

@Test func omitsBlankScope() {
    #expect(render(.init(type: .fix, scope: " ", subject: "x", breaking: false)) == "fix: x")
}

@Test func sanitizesSubject() {
    #expect(render(.init(type: .docs, scope: nil, subject: "Update README.\nmore", breaking: false)) == "docs: update README")
}

@Test func sanitizesWhitespace() {
    #expect(render(.init(type: .fix, scope: nil, subject: "  fix   the\tbug  ", breaking: false)) == "fix: fix the bug")
}

@Test func fitDropsScopeThenTrims() {
    let long = String(repeating: "word ", count: 20)
    let s = fit(.init(type: .refactor, scope: "verylongscope", subject: long, breaking: false))
    #expect(s.count <= 72)
    #expect(s.hasPrefix("refactor: "))
    #expect(!s.hasSuffix(" "))
}

@Test func fitDropsScopeWhenThatSuffices() {
    let subject = String(repeating: "a", count: 60)
    let s = fit(.init(type: .feat, scope: "something", subject: subject, breaking: false))
    #expect(s == "feat: " + subject)
}

@Test func fitKeepsShortMessage() {
    #expect(fit(.init(type: .chore, scope: "deps", subject: "bump x", breaking: false)) == "chore(deps): bump x")
}

@Test func allElevenTypes() {
    #expect(CommitType.allCases.map(\.rawValue) == ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"])
}
