import Foundation
import FMCodeCore

func fail(_ message: String, hint: Bool = true) -> Never {
    var text = "fm-code: \(message)\n"
    if hint { text += "\(doctorHint)\n" }
    FileHandle.standardError.write(Data(text.utf8))
    exit(1)
}

func ask(_ prompt: String) -> String? {
    FileHandle.standardError.write(Data(prompt.utf8))
    return readLine()
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

guard let command = Command.parse(Array(CommandLine.arguments.dropFirst())) else {
    fail("unknown arguments\n\n\(usage)", hint: false)
}

do {
    switch command {
    case .help:
        print(usage)

    case .doctor:
        let results = checks(.gather(cwd: cwd))
        print(renderDoctor(results), terminator: "")
        if results.contains(where: { $0.status == .fail }) { exit(1) }

    case .installHook:
        let me = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "fm-code"
        let url = try installHook(in: cwd, fallback: me)
        print("Installed \(url.path)\n`git commit` will now prefill a suggested message.")

    case .print:
        try preflight(in: cwd)
        print(try await generateCommitMessage(in: cwd))

    case .commit:
        try preflight(in: cwd)
        var message = try await generateCommitMessage(in: cwd)
        print(message)
        loop: while true {
            switch ask("Commit? [y]es / [e]dit / [n]o: ")?.lowercased() {
            case "y", "yes":
                try Git.run(["commit", "-m", message], in: cwd)
                print("Committed.")
                break loop
            case "e", "edit":
                if let edited = ask("Message: ")?.trimmingCharacters(in: .whitespaces), !edited.isEmpty {
                    message = edited
                }
                print(message)
            case "n", "no", nil:
                print("Not committed.")
                break loop
            default:
                continue
            }
        }
    }
} catch let error as CLIError {
    fail(error.description)
} catch let error as GeneratorError {
    fail(error.description)
} catch {
    fail(String(describing: error))
}
