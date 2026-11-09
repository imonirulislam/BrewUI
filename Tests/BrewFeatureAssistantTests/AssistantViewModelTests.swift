import BrewAssistantCore
import BrewCore
import BrewCoreTestSupport
@testable import BrewFeatureAssistant
import BrewRepositoryInterfaces
import Foundation
import Testing

struct AssistantViewModelTests {
    @Test func `an unavailable model blocks requests and says why`() {
        let viewModel = makeViewModel(model: ScriptedModel(availability: .appleIntelligenceNotEnabled))
        viewModel.request = "convert videos"

        viewModel.submit()

        #expect(!viewModel.canSubmit)
        #expect(viewModel.state == .idle)
        #expect(!AssistantCopy.unavailableTitle(for: viewModel.availability).isEmpty)
    }

    @Test func `a blank request cannot be submitted`() {
        let viewModel = makeViewModel(model: ScriptedModel())
        viewModel.request = "   "

        #expect(!viewModel.canSubmit)
    }

    @Test func `a request shows catalogue-backed suggestions`() async throws {
        let viewModel = makeViewModel(model: ScriptedModel(picks: [ModelPick(name: "ffmpeg", reason: "Converts video")]))
        viewModel.request = "convert videos"

        viewModel.submit()
        try await waitUntilSettled(viewModel)

        guard case let .results(suggestions) = viewModel.state else {
            Issue.record("Expected results, got \(viewModel.state)")
            return
        }
        #expect(suggestions.map(\.package.name) == ["ffmpeg"])
        #expect(viewModel.installCommand(for: suggestions[0]) == "brew install ffmpeg")
    }

    @Test func `model errors are shown rather than swallowed`() async throws {
        let viewModel = makeViewModel(model: ScriptedModel(error: .guardrailViolation))
        viewModel.request = "convert videos"

        viewModel.submit()
        try await waitUntilSettled(viewModel)

        guard case let .failed(message) = viewModel.state else {
            Issue.record("Expected failure, got \(viewModel.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func `nothing installs until the user confirms`() {
        let viewModel = makeViewModel(model: ScriptedModel())
        let suggestion = PackageSuggestion(package: Self.ffmpeg, reason: "Converts video")

        viewModel.requestInstall(suggestion)

        #expect(viewModel.pendingInstall == suggestion)
        #expect(viewModel.installing.isEmpty)

        viewModel.confirmInstall()

        #expect(viewModel.pendingInstall == nil)
        #expect(viewModel.installing.contains(suggestion.id))
    }

    @Test func `installed packages are not offered for install`() {
        let installed = InstalledBrewPackage.fixture(name: "ffmpeg", kind: .formula)
        let viewModel = makeViewModel(model: ScriptedModel(), installed: [installed])
        let suggestion = PackageSuggestion(package: Self.ffmpeg, reason: "Converts video")

        viewModel.requestInstall(suggestion)

        #expect(viewModel.isInstalled(suggestion))
        #expect(viewModel.pendingInstall == nil)
    }

    @Test func `casks install with the cask flag`() {
        let viewModel = makeViewModel(model: ScriptedModel())
        let cask = BrewPackage(name: "handbrake", displayName: "HandBrake", kind: .cask, description: "Video transcoder",
                               homepage: "", latestVersion: "1", dependencies: [])

        #expect(viewModel.installCommand(for: PackageSuggestion(package: cask, reason: "")) == "brew install --cask handbrake")
    }

    private static let ffmpeg = BrewPackage(name: "ffmpeg", displayName: "ffmpeg", kind: .formula,
                                            description: "Play, record, convert, and stream audio and video",
                                            homepage: "https://ffmpeg.org", latestVersion: "7.1", dependencies: [])

    private func makeViewModel(model: ScriptedModel, installed: [InstalledBrewPackage] = []) -> AssistantViewModel {
        AssistantViewModel(
            model: model,
            catalogue: StubCatalogueRepository(formulaCatalogue: [Self.ffmpeg], caskCatalogue: []),
            installedRepository: StubInstalledPackagesRepository(packages: installed),
            brewCommandCenter: StubBrewCommandCenter(),
            commandFactory: StubMutatingCommandFactory(),
        )
    }

    private func waitUntilSettled(_ viewModel: AssistantViewModel) async throws {
        for _ in 0 ..< 200 where viewModel.state == .thinking {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.state != .thinking)
    }
}

private struct ScriptedModel: PackageSuggestionModel {
    var availability: AssistantAvailability = .available
    var picks: [ModelPick] = []
    var error: AssistantError?

    func searchTerms(for _: String) async throws -> [String] {
        if let error {
            throw error
        }
        return ["ffmpeg"]
    }

    func choose(for _: String, from _: [SuggestionCandidate]) async throws -> [ModelPick] {
        picks
    }
}
