import Foundation
import FoundationModels

@Generable
struct CommitMessage {
    @Guide(description: "Conventional Commit type", .anyOf(CommitType.allCases.map(\.rawValue)))
    var type: String
    @Guide(description: "Optional short scope, one lowercase word such as a module or area")
    var scope: String?
    @Guide(description: "Imperative summary naming what changed (verb + object, 3 to 8 words), lowercase, no trailing period")
    var subject: String
    @Guide(description: "True only if the change breaks backwards compatibility")
    var breaking: Bool

    var draft: CommitDraft {
        CommitDraft(type: CommitType(rawValue: type) ?? .chore, scope: scope, subject: subject, breaking: breaking)
    }
}

public enum GeneratorError: Error, CustomStringConvertible {
    case modelUnavailable(String)
    public var description: String {
        switch self { case .modelUnavailable(let why): "on-device model unavailable: \(why)" }
    }
}

/// Uses the first draft if it fits; otherwise asks once for a shorter one, then force-fits.
public func finalize(
    maxLength: Int = 72,
    draft: () async throws -> CommitDraft,
    retry: (Int) async throws -> CommitDraft
) async throws -> String {
    let first = render(try await draft())
    if first.count <= maxLength { return first }
    return fit(try await retry(first.count), maxLength: maxLength)
}

let instructions = """
    You write a single-line Conventional Commit message for the staged changes in a git repository.
    Use the git tool in this order: log (only to see the repo's style), then diffStat, then diff.
    Never reuse or copy a previous commit subject; describe only what the staged diff changes.
    Pick the type from the diff: feat for new functionality, fix for bug fixes, docs for documentation only,
    test for tests only, refactor for restructuring without behavior change, chore for tooling or maintenance.
    The subject is imperative and names what changed, shaped like "add <what> to <where>" or "fix <problem> in <where>",
    with the placeholders filled from the file names and code in the diff. No body, no explanation.
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
                to: "Too long (\(length) chars). Give a shorter subject, total ≤ 72 chars.",
                generating: CommitMessage.self
            ).content.draft
        }
    )
}
