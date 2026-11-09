@testable import BrewAssistantCore
import BrewCore
import BrewRepositoryInterfaces
import Foundation
import Testing

struct SuggestionPipelineTests {
    @Test func `an empty request asks the model nothing`() async throws {
        let model = FakeSuggestionModel(terms: ["ffmpeg"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        let suggestions = try await pipeline.suggestions(for: "   \n")

        #expect(suggestions.isEmpty)
        #expect(await model.searchTermRequests.isEmpty)
    }

    @Test func `suggestions come only from catalogue packages`() async throws {
        let model = FakeSuggestionModel(
            terms: ["ffmpeg", "handbrake"],
            picks: [
                ModelPick(name: "ffmpeg", reason: "Converts between video formats"),
                ModelPick(name: "videomagic", reason: "Invented by the model"),
            ],
        )
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        let suggestions = try await pipeline.suggestions(for: "something to convert videos")

        #expect(suggestions.map(\.package.id) == [.formula(name: "ffmpeg")])
        #expect(suggestions.first?.reason == "Converts between video formats")
    }

    @Test func `the model chooses only from what the catalogue returned`() async throws {
        let model = FakeSuggestionModel(terms: ["ffmpeg", "nonexistent"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        _ = try await pipeline.suggestions(for: "convert videos")

        let offered = await model.offeredCandidates
        #expect(offered.map(\.id) == [.formula(name: "ffmpeg")])
    }

    @Test func `no candidates means no second model call`() async throws {
        let model = FakeSuggestionModel(terms: ["nonexistent"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        let suggestions = try await pipeline.suggestions(for: "something obscure")

        #expect(suggestions.isEmpty)
        #expect(await model.chooseCallCount == 0)
    }

    @Test func `duplicate picks collapse to one suggestion`() async throws {
        let model = FakeSuggestionModel(
            terms: ["ffmpeg"],
            picks: [
                ModelPick(name: "ffmpeg", reason: "First"),
                ModelPick(name: "FFmpeg", reason: "Second"),
            ],
        )
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        let suggestions = try await pipeline.suggestions(for: "convert videos")

        #expect(suggestions.map(\.reason) == ["First"])
    }

    @Test func `suggestions are capped`() {
        let names = (1 ... 9).map { "tool\($0)" }

        let suggestions = SuggestionPipeline.validated(
            names.map { ModelPick(name: $0, reason: "Fits") },
            against: names.map(Self.formula),
        )

        #expect(suggestions.count == SuggestionPipeline.maximumSuggestions)
    }

    @Test func `search terms are trimmed, de-duplicated and capped before searching`() async throws {
        let catalogue = RecordingCatalogue()
        let model = FakeSuggestionModel(terms: [" ffmpeg ", "FFMPEG", "", "a", "b", "c", "d", "e"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: catalogue)

        _ = try await pipeline.suggestions(for: "convert videos")

        #expect(await catalogue.queries == ["ffmpeg", "a", "b", "c", "d"])
    }

    @Test func `candidate summaries are shortened to fit the model's context`() async throws {
        let long = String(repeating: "word ", count: 100)
        let catalogue = StubCatalogueRepository(formulaCatalogue: [Self.formula("ffmpeg", description: long)], caskCatalogue: [])
        let model = FakeSuggestionModel(terms: ["ffmpeg"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: catalogue)

        _ = try await pipeline.suggestions(for: "convert videos")

        let summary = try #require(await model.offeredCandidates.first?.summary)
        #expect(summary.count <= SuggestionPipeline.maximumSummaryLength)
    }

    @Test func `catalogue failures reach the caller`() async {
        let model = FakeSuggestionModel(terms: ["ffmpeg"], picks: [])
        let pipeline = SuggestionPipeline(model: model, catalogue: FailingCatalogue())

        await #expect(throws: FailingCatalogue.Failure.self) {
            try await pipeline.suggestions(for: "convert videos")
        }
    }

    @Test func `model failures reach the caller`() async {
        let model = FakeSuggestionModel(terms: [], picks: [], error: AssistantError.guardrailViolation)
        let pipeline = SuggestionPipeline(model: model, catalogue: Self.catalogue)

        await #expect(throws: AssistantError.guardrailViolation) {
            try await pipeline.suggestions(for: "convert videos")
        }
    }

    @Test func `a cask and a formula with the same pick name resolve to the first candidate`() async throws {
        let catalogue = StubCatalogueRepository(
            formulaCatalogue: [Self.formula("docker")],
            caskCatalogue: [BrewPackage(name: "docker", displayName: "Docker Desktop", kind: .cask, description: "App",
                                        homepage: "", latestVersion: "1", dependencies: [])],
        )
        let model = FakeSuggestionModel(terms: ["docker"], picks: [ModelPick(name: "docker", reason: "Containers")])
        let pipeline = SuggestionPipeline(model: model, catalogue: catalogue)

        let suggestions = try await pipeline.suggestions(for: "run containers")

        #expect(suggestions.map(\.package.id) == [.formula(name: "docker")])
    }

    private static let catalogue = StubCatalogueRepository(
        formulaCatalogue: [formula("ffmpeg", description: "Play, record, convert, and stream audio and video"), formula("wget")],
        caskCatalogue: [],
    )

    private static func formula(_ name: String) -> BrewPackage {
        formula(name, description: "\(name) description")
    }

    private static func formula(_ name: String, description: String) -> BrewPackage {
        BrewPackage(name: name, displayName: name, kind: .formula, description: description,
                    homepage: "https://example.com/\(name)", latestVersion: "1.0", dependencies: [])
    }
}

private actor FakeSuggestionModel: PackageSuggestionModel {
    private let terms: [String]
    private let picks: [ModelPick]
    private let error: AssistantError?
    private(set) var searchTermRequests: [String] = []
    private(set) var offeredCandidates: [SuggestionCandidate] = []
    private(set) var chooseCallCount = 0

    init(terms: [String], picks: [ModelPick], error: AssistantError? = nil) {
        self.terms = terms
        self.picks = picks
        self.error = error
    }

    nonisolated var availability: AssistantAvailability {
        .available
    }

    func searchTerms(for request: String) async throws -> [String] {
        searchTermRequests.append(request)
        if let error {
            throw error
        }
        return terms
    }

    func choose(for _: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick] {
        chooseCallCount += 1
        offeredCandidates = candidates
        return picks
    }
}

private actor RecordingCatalogue: CatalogueRepository {
    private(set) var queries: [String] = []

    func package(for _: HomebrewPackageID) async throws -> BrewPackage? {
        nil
    }

    func searchPackages(matching query: String, limit _: Int) async throws -> [BrewPackage] {
        queries.append(query)
        return []
    }
}

private struct FailingCatalogue: CatalogueRepository {
    struct Failure: Error {}

    func package(for _: HomebrewPackageID) async throws -> BrewPackage? {
        throw Failure()
    }

    func searchPackages(matching _: String, limit _: Int) async throws -> [BrewPackage] {
        throw Failure()
    }
}
