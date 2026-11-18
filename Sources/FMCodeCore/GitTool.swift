import Foundation
import FoundationModels

/// The only tool the model gets: allowlisted, read-only git commands.
struct GitTool: Tool {
    let name = "git"
    let description = """
        Run a read-only git command in the repository. \
        diffStat: changed files summary. diff: full staged diff. \
        status: short status. log: last 10 commit subjects (for style).
        """

    @Generable
    struct Arguments {
        @Guide(description: "Which git command to run", .anyOf(ReadOnlyGitCommand.allCases.map(\.rawValue)))
        var command: String
    }

    let cwd: URL
    let runner: ToolGitRunner

    init(cwd: URL, runner: ToolGitRunner) {
        self.cwd = cwd
        self.runner = runner
    }

    func call(arguments: Arguments) async throws -> String {
        try await run(command: arguments.command)
    }

    func run(command: String) async throws -> String {
        guard let cmd = ReadOnlyGitCommand(rawValue: command) else { return "refused: not allowed" }
        let out = try runner.run(cmd, in: cwd)
        if ProcessInfo.processInfo.environment["FM_CODE_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("→ \(runner.rtk == nil ? "" : "rtk ")git \(cmd.args.joined(separator: " ")) (\(out.count) chars)\n".utf8))
        }
        return out.isEmpty ? "(no output)" : truncate(out)
    }
}
