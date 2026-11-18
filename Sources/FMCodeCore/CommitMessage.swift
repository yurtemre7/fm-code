// Commit message model and rendering.
import Foundation

public enum CommitType: String, CaseIterable, Sendable {
    case feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
}

public struct CommitDraft: Sendable, Equatable {
    public var type: CommitType
    public var subject: String
    public var breaking: Bool

    public init(type: CommitType, subject: String, breaking: Bool) {
        self.type = type
        self.subject = subject
        self.breaking = breaking
    }
}

/// Collapses whitespace in a single line.
private func collapse(_ s: Substring) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Matches a type prefix the model repeated inside the subject, e.g. `Fix(ui)!: `.
private var repeatedType: Regex<AnyRegexOutput> { try! Regex(
    "^(?i:\(CommitType.allCases.map(\.rawValue).joined(separator: "|")))(\\([^)]*\\))?!?:\\s*") }

func cleanSubject(_ raw: String) -> String {
    let firstLine = raw.split(whereSeparator: \.isNewline).map(collapse).first { !$0.isEmpty } ?? ""
    var s = firstLine
    if let m = s.prefixMatch(of: repeatedType) { s = String(s[m.range.upperBound...]) }
    while s.hasSuffix(".") { s.removeLast() }
    s = s.trimmingCharacters(in: .whitespaces)
    // Lowercase "Add" → "add", but keep acronyms/names like "README" or "API".
    guard let first = s.first, s.dropFirst().first?.isUppercase != true else { return s }
    return first.lowercased() + s.dropFirst()
}

/// `type: subject` — never `type(scope): subject`.
private func header(_ d: CommitDraft) -> String {
    "\(d.type.rawValue)\(d.breaking ? "!" : ""): "
}

public func render(_ d: CommitDraft) -> String {
    header(d) + cleanSubject(d.subject)
}

public func fit(_ d: CommitDraft, maxLength: Int = 72) -> String {
    let full = render(d)
    if full.count <= maxLength { return full }
    let head = header(d)
    let subject = cleanSubject(d.subject)

    let budget = max(0, maxLength - head.count)
    var cut = String(subject.prefix(budget))
    if let space = cut.lastIndex(of: " "), subject.count > budget {
        cut = String(cut[..<space])
    }
    return head + cut.trimmingCharacters(in: .whitespaces)
}
