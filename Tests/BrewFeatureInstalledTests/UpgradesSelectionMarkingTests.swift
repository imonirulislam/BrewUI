import BrewCore
import BrewCoreTestSupport
@testable import BrewFeatureInstalled
import BrewRepositoryInterfaces
import Testing

@MainActor
struct UpgradesSelectionMarkingTests {
    @Test func `nothing marked keeps Upgrade All behaviour`() {
        let viewModel = makeViewModel()

        #expect(!viewModel.isUpgradingMarkedSelection)
        #expect(viewModel.upgradeSelection == .all)
        #expect(viewModel.upgradeActionCount == 3)
    }

    @Test func `marked rows become an explicit batch in list order`() {
        let viewModel = makeViewModel()

        viewModel.toggleMark(Self.wget.id)
        viewModel.toggleMark(Self.git.id)

        #expect(viewModel.isUpgradingMarkedSelection)
        #expect(viewModel.upgradeSelection == .explicit(["git", "wget"]))
        #expect(viewModel.bulkUpgradeDisplayCommand == "brew upgrade git wget")
        #expect(viewModel.upgradeActionCount == 2)
    }

    @Test func `toggling a marked row unmarks it`() {
        let viewModel = makeViewModel()

        viewModel.toggleMark(Self.git.id)
        viewModel.toggleMark(Self.git.id)

        #expect(!viewModel.isMarked(Self.git.id))
        #expect(viewModel.upgradeSelection == .all)
    }

    @Test func `marked rows hidden by search are not upgraded`() {
        let viewModel = makeViewModel()
        viewModel.toggleMark(Self.git.id)
        viewModel.toggleMark(Self.wget.id)

        viewModel.searchQuery = "wget"

        #expect(viewModel.upgradeSelection == .explicit(["wget"]))
        #expect(viewModel.upgradeActionCount == 1)
    }

    @Test func `marked rows hidden by scope are not upgraded`() {
        let viewModel = makeViewModel()
        viewModel.toggleMark(Self.git.id)
        viewModel.toggleMark(Self.slack.id)

        viewModel.scope = .casks

        #expect(viewModel.upgradeSelection == .explicit(["slack"]))
    }

    @Test func `when every marked row is filtered out the filters decide again`() {
        let viewModel = makeViewModel()
        viewModel.toggleMark(Self.git.id)

        viewModel.scope = .casks

        #expect(!viewModel.isUpgradingMarkedSelection)
        #expect(viewModel.upgradeSelection == .casks)
    }

    @Test func `deselect all clears every mark`() {
        let viewModel = makeViewModel()
        viewModel.toggleMark(Self.git.id)
        viewModel.toggleMark(Self.wget.id)

        viewModel.clearMarks()

        #expect(viewModel.markedPackageIDs.isEmpty)
        #expect(viewModel.upgradeSelection == .all)
    }

    @Test func `upgrading the marked selection runs exactly the shown command and clears marks`() async {
        let center = SubmitRecordingCommandCenter()
        let viewModel = makeViewModel(center: center)
        viewModel.toggleMark(Self.slack.id)
        viewModel.toggleMark(Self.git.id)
        let shown = viewModel.bulkUpgradeDisplayCommand

        viewModel.upgradeAll()
        await center.waitForSubmitCallCount(1)

        let command = await center.recordedCommands.first
        #expect(command.map { "brew " + $0.arguments.joined(separator: " ") } == shown)
        #expect(viewModel.markedPackageIDs.isEmpty)
    }

    @Test func `toggling the active row marks the selected package`() {
        let viewModel = makeViewModel()
        viewModel.setSelection(Self.wget.id)

        viewModel.toggleMarkForActiveSelection()

        #expect(viewModel.isMarked(Self.wget.id))
    }

    private static let git = InstalledBrewPackage.fixture(name: "git", kind: .formula, outdated: true)
    private static let wget = InstalledBrewPackage.fixture(name: "wget", kind: .formula, outdated: true)
    private static let slack = InstalledBrewPackage.fixture(name: "slack", kind: .cask, outdated: true)

    private func makeViewModel(center: any BrewCommandCenter = StubBrewCommandCenter()) -> UpgradesViewModel {
        UpgradesViewModel(
            repository: StubInstalledPackagesRepository(packages: [Self.git, Self.slack, Self.wget]),
            brewCommandCenter: center,
            commandFactory: StubMutatingCommandFactory(),
        )
    }
}
