import BrewCore
import BrewCoreTestSupport
@testable import BrewFeatureGoTo
import BrewRepositoryInterfaces
import Testing

@MainActor
struct GoToViewModelTests {
    @Test func `an empty query lists every page`() {
        let viewModel = makeViewModel()

        #expect(viewModel.results.map(\.title) == ["Installed", "Upgrades", "Discover", "Taps"])
    }

    @Test func `pages match by prefix before substring`() async {
        let viewModel = makeViewModel()

        await viewModel.search("up")

        #expect(viewModel.results.first?.destination == .page("upgrades"))
    }

    @Test func `installed packages are found by name and open in Installed`() async {
        let viewModel = makeViewModel()

        await viewModel.search("wge")

        #expect(viewModel.results.contains { $0.destination == .installedPackage(.formula(name: "wget")) })
    }

    @Test func `catalogue packages that are not installed open Discover with their name`() async {
        let viewModel = makeViewModel()

        await viewModel.search("ffm")

        #expect(viewModel.results.map(\.destination) == [.discover("ffmpeg")])
    }

    @Test func `installed packages are not repeated as catalogue results`() async {
        let viewModel = makeViewModel()

        await viewModel.search("wget")

        #expect(viewModel.results.filter { $0.destination == .discover("wget") }.isEmpty)
    }

    @Test func `exact name matches lead`() async {
        let viewModel = makeViewModel(installed: [
            .fixture(name: "gitleaks", kind: .formula),
            .fixture(name: "git", kind: .formula),
        ])

        await viewModel.search("git")

        #expect(viewModel.results.first?.destination == .installedPackage(.formula(name: "git")))
    }

    @Test func `arrow keys move the highlight within bounds`() {
        let viewModel = makeViewModel()
        #expect(viewModel.highlightedIndex == 0)

        viewModel.moveHighlight(by: 1)
        viewModel.moveHighlight(by: 10)
        #expect(viewModel.highlightedIndex == viewModel.results.count - 1)

        viewModel.moveHighlight(by: -20)
        #expect(viewModel.highlightedIndex == 0)
    }

    @Test func `a new search resets the highlight`() async {
        let viewModel = makeViewModel()
        viewModel.moveHighlight(by: 2)

        await viewModel.search("dis")

        #expect(viewModel.highlightedIndex == 0)
        #expect(viewModel.highlightedResult?.destination == .page("discover"))
    }

    @Test func `no matches leaves nothing to activate`() async {
        let viewModel = makeViewModel()

        await viewModel.search("zzzz-nothing")

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.highlightedResult == nil)
    }

    private func makeViewModel(installed: [InstalledBrewPackage]? = nil) -> GoToViewModel {
        GoToViewModel(
            pages: [
                GoToPage(id: "installed", title: "Installed", systemImage: "cube.box.fill"),
                GoToPage(id: "upgrades", title: "Upgrades", systemImage: "arrow.up.circle"),
                GoToPage(id: "discover", title: "Discover", systemImage: "magnifyingglass"),
                GoToPage(id: "taps", title: "Taps", systemImage: "arrow.triangle.branch"),
            ],
            installedRepository: StubInstalledPackagesRepository(packages: installed ?? [
                .fixture(name: "wget", kind: .formula),
                .fixture(name: "slack", kind: .cask),
            ]),
            catalogueRepository: StubCatalogueRepository(
                formulaCatalogue: [
                    BrewPackage(name: "ffmpeg", displayName: "ffmpeg", kind: .formula, description: "Video tools",
                                homepage: "", latestVersion: "7.1", dependencies: []),
                    BrewPackage(name: "wget", displayName: "wget", kind: .formula, description: "Downloader",
                                homepage: "", latestVersion: "1.25", dependencies: []),
                ],
                caskCatalogue: [],
            ),
        )
    }
}
