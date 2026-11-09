import BrewCore
import BrewCoreTestSupport
@testable import BrewFeatureMenuBar
import Testing

@MainActor
struct MenuBarSummaryTests {
    @Test func `nothing outdated reads as up to date with no badge`() {
        let summary = MenuBarSummary(outdated: [])

        #expect(summary.badge == nil)
        #expect(summary.rows.isEmpty)
        #expect(summary.hiddenCount == 0)
    }

    @Test func `the badge counts every outdated package`() {
        let summary = MenuBarSummary(outdated: (1 ... 3).map { Self.outdated("tool\($0)") })

        #expect(summary.badge == "3")
    }

    @Test func `rows show installed and available versions in name order`() {
        let summary = MenuBarSummary(outdated: [
            Self.outdated("wget", installed: "1.24", latest: "1.25"),
            Self.outdated("git", installed: "2.46.0", latest: "2.47.1"),
        ])

        #expect(summary.rows.map(\.name) == ["git", "wget"])
        #expect(summary.rows.first?.versions == "2.46.0 → 2.47.1")
    }

    @Test func `the list is capped and reports how many are hidden`() {
        let summary = MenuBarSummary(outdated: (1 ... 14).map { Self.outdated(String(format: "tool%02d", $0)) })

        #expect(summary.rows.count == MenuBarSummary.maximumRows)
        #expect(summary.hiddenCount == 14 - MenuBarSummary.maximumRows)
    }

    @Test func `a package without an installed version shows only the available one`() {
        let summary = MenuBarSummary(outdated: [Self.outdated("git", installed: nil, latest: "2.47.1")])

        #expect(summary.rows.first?.versions == "→ 2.47.1")
    }

    private static func outdated(_ name: String, installed: String? = "1.0", latest: String = "2.0") -> InstalledBrewPackage {
        var package = InstalledBrewPackage.fixture(name: name, kind: .formula, outdated: true)
        package.installedVersions = installed.map { [$0] } ?? []
        package.linkedKeg = nil
        package.package.latestVersion = latest
        return package
    }
}
