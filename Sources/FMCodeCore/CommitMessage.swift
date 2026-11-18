// Commit message model and rendering.
import Foundation

public enum CommitType: String, CaseIterable, Sendable {
    case feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
}

public struct CommitDraft: Sendable, Equatable {
    public var type: CommitType
    public var scope: String?
    public var subject: String
    public var breaking: Bool

    public init(type: CommitType, scope: String?, subject: String, breaking: Bool) {
        self.type = type
        self.scope = scope
        self.subject = subject
        self.breaking = breaking
    }
}

/// Collapses whitespace in a single line.
private func collapse(_ s: Substring) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

func cleanSubject(_ raw: String) -> String {
    let firstLine = raw.split(whereSeparator: \.isNewline).first.map(collapse) ?? ""
    var s = firstLine
    while s.hasSuffix(".") { s.removeLast() }
    s = s.trimmingCharacters(in: .whitespaces)
    guard let first = s.first else { return s }
    return first.lowercased() + s.dropFirst()
}

func cleanScope(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let s = collapse(Substring(raw)).replacingOccurrences(of: " ", with: "-")
    return s.isEmpty ? nil : s
}

private func header(_ d: CommitDraft, scope: String?) -> String {
    "\(d.type.rawValue)\(scope.map { "(\($0))" } ?? "")\(d.breaking ? "!" : ""): "
}

public func render(_ d: CommitDraft) -> String {
    header(d, scope: cleanScope(d.scope)) + cleanSubject(d.subject)
}

public func fit(_ d: CommitDraft, maxLength: Int = 72) -> String {
    let full = render(d)
    if full.count <= maxLength { return full }
    let head = header(d, scope: nil)
    let subject = cleanSubject(d.subject)
    if head.count + subject.count <= maxLength { return head + subject }

    let budget = max(0, maxLength - head.count)
    var cut = String(subject.prefix(budget))
    if let space = cut.lastIndex(of: " "), subject.count > budget {
        cut = String(cut[..<space])
    }
    return head + cut.trimmingCharacters(in: .whitespaces)
}
