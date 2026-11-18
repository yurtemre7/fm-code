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

/// Uses the first draft if it fits and has a subject; otherwise asks once for a better one,
/// then force-fits. If the retry itself fails, the first draft is force-fit instead.
public func finalize(
    maxLength: Int = 72,
    draft: () async throws -> CommitDraft,
    retry: (Int) async throws -> CommitDraft
) async throws -> String {
    let first = try await draft()
    let rendered = render(first)
    let empty = cleanSubject(first.subject).isEmpty
    if rendered.count <= maxLength && !empty { return rendered }
    guard let second = try? await retry(rendered.count) else {
        if empty { throw GeneratorError.emptyMessage }
        return fit(first, maxLength: maxLength)
    }
    return fit(second, maxLength: maxLength)
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
    return try await finalize(
        draft: {
            try await session.respond(to: "Write the commit message for the staged changes.", generating: CommitMessage.self).content.draft
        },
        retry: { length in
            try await session.respond(
                to: "That message was \(length) chars or had an empty subject. Give a short, non-empty subject, total ≤ 72 chars.",
                generating: CommitMessage.self
            ).content.draft
        }
    )
}
