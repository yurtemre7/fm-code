import Foundation
import Testing
@testable import FMCodeCore

let good = DoctorInputs(
    macOS: .init(majorVersion: 27, minorVersion: 2, patchVersion: 0), isAppleSilicon: true,
    model: .available, gitVersion: "2.50.1", rtkVersion: "1.2.0",
    repo: .staged(files: 2, hookInstalled: true))

@Test func allGoodHasNoFailsOrWarns() {
    #expect(checks(good).allSatisfy { $0.status == .ok })
}

@Test func modelOffIsFailWithFix() {
    var i = good; i.model = .appleIntelligenceOff
    let c = checks(i).first { $0.status == .fail }
    #expect(c?.detail?.contains("Apple Intelligence") == true)
}

@Test func missingRTKIsOnlyWarn() {
    var i = good; i.rtkVersion = nil
    #expect(checks(i).contains { $0.status == .warn && $0.title.contains("rtk") })
    #expect(!checks(i).contains { $0.status == .fail })
}

@Test func oldMacOSFails() {
    var i = good; i.macOS.majorVersion = 15
    #expect(checks(i).contains { $0.status == .fail })
}

@Test func intelFails() {
    var i = good; i.isAppleSilicon = false
    #expect(checks(i).contains { $0.status == .fail })
}

@Test func repoStatesAreWarnings() {
    for repo in [RepoState.notARepo, .nothingStaged, .staged(files: 1, hookInstalled: false)] {
        var i = good; i.repo = repo
        #expect(checks(i).contains { $0.status == .warn })
        #expect(!checks(i).contains { $0.status == .fail })
    }
    var i = good; i.repo = .staged(files: 1, hookInstalled: false)
    #expect(checks(i).contains { $0.detail?.contains("fm-code --hook") == true })
}

@Test func renderSummaries() {
    let out = renderDoctor(checks(good))
    #expect(out.hasSuffix("No issues found!\n"))
    #expect(out.contains("[✓]"))
    #expect(out.contains("diff --staged --stat"))
    var i = good; i.gitVersion = nil
    let bad = renderDoctor(checks(i))
    #expect(bad.contains("[✗]"))
    #expect(bad.contains("1 issue"))
}

@Test func parsesDoctor() { #expect(Command.parse(["doctor"]) == .doctor) }

@Test func gatherReadsRealRepo() throws {
    let repo = try makeTempRepo(stage: ["a.txt": "x\n", "b.txt": "y\n"])
    let i = DoctorInputs.gather(cwd: repo, env: ["FM_CODE_NO_RTK": "1"])
    #expect(i.repo == .staged(files: 2, hookInstalled: false))
    #expect(i.gitVersion != nil)
    #expect(i.rtkVersion == nil)
}
