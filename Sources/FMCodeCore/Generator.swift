import Foundation
import FoundationModels

@Generable
struct CommitMessage {
    @Guide(description: "Conventional Commit type", .anyOf(CommitType.allCases.map(\.rawValue)))
    var type: String
    @Guide(description: "Optional short scope, one lowercase word such as a module or area")
    var scope: String?
    @Guide(description: "Imperative, lowercase summary of the change, no trailing period, under 50 characters")
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
    Use the git tool to look at the changes: start with diffStat, then diff. Use log to match the repo's style.
    Describe what the change does, in imperative mood. No body, no explanation.
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
