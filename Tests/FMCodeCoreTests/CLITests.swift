import Foundation
import Testing
@testable import FMCodeCore

@Test func parsesArgs() {
    #expect(Command.parse([]) == .print)
    #expect(Command.parse(["-c"]) == .commit)
    #expect(Command.parse(["--commit"]) == .commit)
    #expect(Command.parse(["--hook"]) == .installHook)
    #expect(Command.parse(["-h"]) == .help)
    #expect(Command.parse(["--help"]) == .help)
    #expect(Command.parse(["--wat"]) == nil)
    #expect(Command.parse(["-c", "extra"]) == nil)
}

@Test func preflightNotARepo() throws {
    let dir = try makeTempDir()
    #expect(throws: CLIError.notARepo) { try preflight(in: dir) }
}

@Test func preflightNothingStaged() throws {
    let repo = try makeTempRepo(stage: [:])
    #expect(throws: CLIError.nothingStaged) { try preflight(in: repo) }
}

@Test func preflightFromSubdirectory() throws {
    let repo = try makeTempRepo(stage: ["d/a.txt": "x\n"])
    try preflight(in: repo.appending(path: "d"))
}

@Test func hookGuardsOnSource() {
    let s = hookScript(fallback: "/opt/fm-code")
    #expect(s.hasPrefix("#!/bin/sh\n"))
    #expect(s.contains("[ -n \"$2\" ] && exit 0"))
    #expect(s.contains("/opt/fm-code"))
}

@Test func installHookRespectsHooksPathAndRefusesOverwrite() throws {
    let repo = try makeTempRepo(stage: [:])
    _ = try Git.run(["config", "core.hooksPath", "myhooks"], in: repo)
    let url = try installHook(in: repo, fallback: "fm-code")
    #expect(url.path.hasSuffix("myhooks/prepare-commit-msg"))
    #expect(FileManager.default.isExecutableFile(atPath: url.path))
    #expect(throws: CLIError.self) { try installHook(in: repo, fallback: "fm-code") }
}

@Test func installHookDefaultLocationFromSubdir() throws {
    let repo = try makeTempRepo(stage: ["d/a.txt": "x\n"])
    let url = try installHook(in: repo.appending(path: "d"), fallback: "fm-code")
    #expect(url.standardizedFileURL.path == repo.appending(path: ".git/hooks/prepare-commit-msg").standardizedFileURL.path)
}

@Test func hookWritesMessageAndSkipsWhenSourceGiven() throws {
    let repo = try makeTempRepo(stage: [:])
    let fake = try makeFakeRTK(script: "echo 'feat: from hook'").appending(path: "rtk")  // any executable works
    let hook = try installHook(in: repo, fallback: fake.path)
    let msgFile = repo.appending(path: "MSG")

    try "orig\n".write(to: msgFile, atomically: true, encoding: .utf8)
    _ = try runProcess(hook, [msgFile.path, "message"], in: repo)
    #expect(try String(contentsOf: msgFile, encoding: .utf8) == "orig\n")

    _ = try runProcess(hook, [msgFile.path], in: repo)
    #expect(try String(contentsOf: msgFile, encoding: .utf8).hasPrefix("feat: from hook\n"))
}
