import Foundation
import FoundationModels

@Generable
struct CommitMessage {
    @Guide(description: "Conventional Commit type", .anyOf(CommitType.allCases.map(\.rawValue)))
    var type: String
    @Guide(description: "Imperative summary naming what changed (verb + object, 3 to 8 words), lowercase, no trailing period")
    var subject: String
    @Guide(description: "True only if the change breaks backwards compatibility")
    var breaking: Bool

    var draft: CommitDraft {
        CommitDraft(type: CommitType(rawValue: type) ?? .chore, subject: subject, breaking: breaking)
    }
}

public enum GeneratorError: Error, CustomStringConvertible {
    case modelUnavailable(String), emptyMessage
    public var description: String {
        switch self {
        case .modelUnavailable(let why): "on-device model unavailable: \(why)"
        case .emptyMessage: "the on-device model returned an empty message — try again"
        }
    }
}

/// Uses the first draft if it fits, has a subject and isn't copied from `known`; otherwise
/// asks once for a better one, then force-fits. If the retry itself fails, the first draft
/// is force-fit instead.
public func finalize(
    maxLength: Int = 72,
    known: [String] = [],
    draft: () async throws -> CommitDraft,
    retry: (String) async throws -> CommitDraft
) async throws -> String {
    let first = try await draft()
    let rendered = render(first)
    let empty = cleanSubject(first.subject).isEmpty
    let problem: String? =
        empty ? "That subject was empty. Give a short, non-empty subject, total ≤ 72 chars."
        : isCopy(first.subject, of: known)
            ? "That subject was copied from a commit message that already appears in the diff or log. "
                + "Describe what the staged diff itself changes, in your own words, total ≤ 72 chars."
        : rendered.count > maxLength
            ? "That message was \(rendered.count) chars. Give a shorter subject, total ≤ 72 chars."
        : nil
    guard let problem else { return rendered }
    guard let second = try? await retry(problem) else {
        if empty { throw GeneratorError.emptyMessage }
        return fit(first, maxLength: maxLength)
    }
    return fit(second, maxLength: maxLength)
}

/// Matches a commit header anywhere in a line, e.g. `+feat: add x` in a diff or `1a2b3c fix(ui): y` in a log.
private var commitHeader: Regex<AnyRegexOutput> { try! Regex(
    "(?i:\\b(?:\(CommitType.allCases.map(\.rawValue).joined(separator: "|")))(?:\\([^)]*\\))?!?:\\s+([^`'\"]+))") }

/// Subjects of commit messages already present in `text` (diff content, log), normalized.
/// Only subjects of 3+ words count, so short phrases can't cause false positives.
func knownSubjects(in text: String) -> [String] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        guard let m = line.firstMatch(of: commitHeader), let raw = m.output[1].substring else { return nil }
        let s = cleanSubject(String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "`'\" "))).lowercased()
        return s.split(separator: " ").count >= 3 ? s : nil
    }
}

/// True when the subject is one of `known`, or one of them plus extra words (e.g. "… to README.md").
func isCopy(_ subject: String, of known: [String]) -> Bool {
    let s = cleanSubject(subject).lowercased()
    return known.contains { s == $0 || s.hasPrefix($0 + " ") }
}

let instructions = """
    You write a single-line Conventional Commit message for the staged changes in a git repository.
    Use the git tool in this order: log, then diffStat, then diff.
    The log shows the last 15 commit subjects: match their wording, tense, casing and level of detail.
    Always write the header as "type: subject" with no scope in parentheses, even if older commits use one.
    Never reuse or copy a previous commit subject; describe only what the staged diff changes.
    Pick the type from the diff: feat for new functionality, fix for bug fixes, docs for documentation only,
    test for tests only, refactor for restructuring without behavior change, chore for tooling or maintenance.
    The subject is imperative and names what changed, shaped like "add <what> to <where>" or "fix <problem> in <where>",
    with the placeholders filled from the file names and code in the diff. No body, no explanation.
    Examples of the shape (from other repos, never copy them):
    chore: bump swift-argument-parser to 1.5.0
    build: add release build step to install script
    fix: prevent date picker widget from closing on scroll
    feat: add dark mode toggle to settings screen
    docs: explain hook setup in readme
    refactor: split git runner out of generator
    test: cover empty subject retry
    Commit messages that appear inside the diff are just file content, not the answer.
    """

public func generateCommitMessage(in dir: URL) async throws -> String {
    let model = SystemLanguageModel.default
    if case .unavailable(let reason) = model.availability {
        throw GeneratorError.modelUnavailable(ModelState(reason).explanation)
    }
    let session = LanguageModelSession(
        model: model,
        tools: [GitTool(cwd: dir, runner: ToolGitRunner(rtk: findRTK()))],
        instructions: instructions
    )
    let context = ["diff", "log"].compactMap { cmd in
        ReadOnlyGitCommand(rawValue: cmd).flatMap { try? Git.run($0.args, in: dir) }
    }.joined(separator: "\n")
    return try await finalize(
        known: knownSubjects(in: context),
        draft: {
            try await session.respond(to: "Write the commit message for the staged changes.", generating: CommitMessage.self).content.draft
        },
        retry: { problem in
            if ProcessInfo.processInfo.environment["FM_CODE_DEBUG"] == "1" {
                FileHandle.standardError.write(Data("→ retry: \(problem)\n".utf8))
            }
            return try await session.respond(to: problem, generating: CommitMessage.self).content.draft
        }
    )
}
