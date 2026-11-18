import Foundation
import FoundationModels
import Synchronization

/// The only tool the model gets: allowlisted, read-only git commands.
struct GitTool: Tool {
    let name = "git"
    let description = """
        Run a read-only git command in the repository. \
        diffStat: changed files summary. diff: full staged diff. \
        status: short status. log: last 15 commit subjects (for style).
        """

    @Generable
    struct Arguments {
        @Guide(description: "Which git command to run", .anyOf(ReadOnlyGitCommand.allCases.map(\.rawValue)))
        var command: String
    }

    let cwd: URL
    let runner: ToolGitRunner
    private let state: Budget

    /// `budget` caps the total characters returned across all calls in a session,
    /// keeping the transcript inside the on-device model's context window.
    init(cwd: URL, runner: ToolGitRunner, budget: Int = 8000) {
        self.cwd = cwd
        self.runner = runner
        self.state = Budget(budget)
    }

    func call(arguments: Arguments) async throws -> String {
        try await run(command: arguments.command)
    }

    func run(command: String) async throws -> String {
        guard let cmd = ReadOnlyGitCommand(rawValue: command) else { return "refused: not allowed" }
        let reply = state.reply(for: cmd) {
            do {
                let out = try runner.run(cmd, in: cwd)
                return out.isEmpty ? "(no output)" : out
            } catch {
                // e.g. `git log` in a repo with no commits: tell the model, don't abort.
                return "git error: \(error)"
            }
        }
        if ProcessInfo.processInfo.environment["FM_CODE_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("→ \(runner.rtk == nil ? "" : "rtk ")git \(cmd.args.joined(separator: " ")) (\(reply.count) chars)\n".utf8))
        }
        return reply
    }
}

/// Tracks which commands were already answered and how much output budget is left.
private final class Budget: Sendable {
    private let state: Mutex<(seen: Set<ReadOnlyGitCommand>, remaining: Int)>

    init(_ total: Int) { state = Mutex((seen: [], remaining: total)) }

    func reply(for cmd: ReadOnlyGitCommand, produce: () -> String) -> String {
        state.withLock { s in
            if s.seen.contains(cmd) { return "(already shown above)" }
            if s.remaining <= 0 { return "(output budget used up — write the message now)" }
            s.seen.insert(cmd)
            let out = truncate(produce(), limit: min(6000, s.remaining))
            s.remaining -= out.count
            return out
        }
    }
}
