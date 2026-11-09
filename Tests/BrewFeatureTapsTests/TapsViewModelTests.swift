import BrewCore
import BrewCoreTestSupport
@testable import BrewFeatureTaps
import BrewRepositoryInterfaces
import Foundation
import Testing

@MainActor
struct TapsViewModelTests {
    @Test func `the first tap is selected by default`() {
        let viewModel = makeViewModel()

        #expect(viewModel.selectedTap?.name == "anomalyco/tap")
    }

    @Test func `arrow keys move the selection and stop at either end`() {
        let viewModel = makeViewModel()

        viewModel.selectNext()
        #expect(viewModel.selectedTap?.name == "homebrew/core")
        viewModel.selectNext()
        #expect(viewModel.selectedTap?.name == "homebrew/core")

        viewModel.selectPrevious()
        viewModel.selectPrevious()
        #expect(viewModel.selectedTap?.name == "anomalyco/tap")
    }

    @Test func `installed packages are attributed to their tap`() {
        let viewModel = makeViewModel(installed: [
            .fixture(name: "opencode", kind: .formula, tap: "anomalyco/tap"),
            .fixture(name: "git", kind: .formula, tap: "homebrew/core"),
        ])

        #expect(viewModel.installedPackages(from: Self.thirdParty).map(\.name) == ["opencode"])
    }

    @Test(arguments: ["someone/tools", "my-org/homebrew.things"])
    func `well-formed new tap names can be added`(name: String) {
        let viewModel = makeViewModel()
        viewModel.newTapName = name

        #expect(viewModel.canAddTap)
    }

    @Test(arguments: ["", "someone", "someone/tools/extra", "some one/tools", "anomalyco/tap", "-rf/x", "a/b; rm -rf ~"])
    func `malformed or existing tap names cannot be added`(name: String) {
        let viewModel = makeViewModel()
        viewModel.newTapName = name

        #expect(!viewModel.canAddTap)
    }

    @Test func `adding asks first and then runs exactly brew tap`() async {
        let center = RecordingCommandCenter()
        let repository = FakeTapsRepository(taps: [Self.thirdParty, Self.core])
        let viewModel = makeViewModel(repository: repository, center: center)
        viewModel.newTapName = " someone/tools "

        viewModel.requestAdd()
        #expect(viewModel.pendingAction?.command.displayCommand == "brew tap someone/tools")
        #expect(await center.commands.isEmpty)

        await viewModel.confirmPendingAction()

        #expect(await center.commands.map(\.arguments) == [["tap", "someone/tools"]])
        #expect(repository.forcedLoads == 1)
        #expect(viewModel.newTapName.isEmpty)
    }

    @Test func `official taps cannot be removed`() {
        let viewModel = makeViewModel()

        #expect(viewModel.removalBlockReason(for: Self.core) != nil)
    }

    @Test func `taps with installed packages cannot be removed`() {
        let viewModel = makeViewModel(installed: [.fixture(name: "opencode", kind: .formula, tap: "anomalyco/tap")])

        #expect(viewModel.removalBlockReason(for: Self.thirdParty) != nil)
    }

    @Test func `removing an unused third-party tap runs brew untap after confirmation`() async {
        let center = RecordingCommandCenter()
        let viewModel = makeViewModel(center: center)

        viewModel.requestRemove(Self.thirdParty)
        await viewModel.confirmPendingAction()

        #expect(await center.commands.map(\.arguments) == [["untap", "anomalyco/tap"]])
    }

    @Test func `a failed command is shown`() async {
        let center = RecordingCommandCenter(failure: BrewCommandError.failed(exitCode: 1, stderr: "Error: Invalid tap name"))
        let viewModel = makeViewModel(center: center)
        viewModel.newTapName = "someone/tools"

        viewModel.requestAdd()
        await viewModel.confirmPendingAction()

        #expect(viewModel.actionError != nil)
    }

    private static let thirdParty = BrewTap(
        name: "anomalyco/tap", remote: URL(string: "https://github.com/anomalyco/homebrew-tap"), isOfficial: false,
        isTrusted: false, isPrivate: false, formulaNames: ["opencode"], caskTokens: [], lastCommit: "2 days ago",
    )
    private static let core = BrewTap(
        name: "homebrew/core", remote: nil, isOfficial: true, isTrusted: true, isPrivate: false,
        formulaNames: [], caskTokens: [], lastCommit: nil,
    )

    private func makeViewModel(
        repository: FakeTapsRepository? = nil,
        installed: [InstalledBrewPackage] = [],
        center: any BrewCommandCenter = RecordingCommandCenter(),
    ) -> TapsViewModel {
        TapsViewModel(
            repository: repository ?? FakeTapsRepository(taps: [Self.thirdParty, Self.core]),
            installedRepository: StubInstalledPackagesRepository(packages: installed),
            brewCommandCenter: center,
        )
    }
}

@MainActor
private final class FakeTapsRepository: TapsRepository {
    private(set) var state: LoadState<[BrewTap], any Error>
    private(set) var forcedLoads = 0

    init(taps: [BrewTap]) {
        state = .loaded(taps)
    }

    func load(forceRefresh: Bool) async {
        if forceRefresh {
            forcedLoads += 1
        }
    }
}

private actor RecordingCommandCenter: BrewCommandCenter {
    private(set) var commands: [BrewCommand] = []
    private let failure: (any Error)?

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    func phase(for _: BrewOperationID) async -> BrewOperationPhase {
        .idle
    }

    func runningPhases() async -> [BrewOperationID: BrewOperationPhase] {
        [:]
    }

    func phaseChanges(for _: BrewOperationID) async -> AsyncStream<BrewOperationPhase> {
        AsyncStream { $0.finish() }
    }

    func allPhaseChanges() async -> AsyncStream<(BrewOperationID, BrewOperationPhase)> {
        AsyncStream { $0.finish() }
    }

    func allOutputChanges() async -> AsyncStream<(BrewOperationID, BrewCommandOutputLine)> {
        AsyncStream { $0.finish() }
    }

    func capture(_: BrewCommand, id _: BrewOperationID) async throws -> CommandOutput {
        CommandOutput(standardOutput: "", standardError: "", terminationStatus: 0)
    }

    func perform(_ command: BrewCommand, id _: BrewOperationID) async throws {
        commands.append(command)
        if let failure {
            throw failure
        }
    }
}
