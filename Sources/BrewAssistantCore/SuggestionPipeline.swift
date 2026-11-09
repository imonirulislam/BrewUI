//
//  SuggestionPipeline.swift
//  BrewAssistantCore
//

import BrewCore
import BrewRepositoryInterfaces
import Foundation

/// Plan → catalogue search → pick → validate. Every suggestion is a package the catalogue returned,
/// so model output never names something Homebrew does not have.
public struct SuggestionPipeline: Sendable {
    public static let maximumSearchTerms = 5
    public static let resultsPerTerm = 4
    public static let maximumCandidates = 12
    public static let maximumSuggestions = 5
    /// The on-device model has a 4,096-token window shared by instructions, candidates and output.
    public static let maximumSummaryLength = 90

    private let model: any PackageSuggestionModel
    private let catalogue: any CatalogueRepository

    public init(model: any PackageSuggestionModel, catalogue: any CatalogueRepository) {
        self.model = model
        self.catalogue = catalogue
    }

    public func suggestions(for request: String) async throws -> [PackageSuggestion] {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequest.isEmpty else {
            return []
        }

        let terms = try await Self.normalisedTerms(model.searchTerms(for: trimmedRequest))
        let candidates = try await searchCatalogue(for: terms)
        guard !candidates.isEmpty else {
            return []
        }
        try Task.checkCancellation()

        let picks = try await model.choose(for: trimmedRequest, from: candidates.map(Self.candidate))
        return Self.validated(picks, against: candidates)
    }

    private func searchCatalogue(for terms: [String]) async throws -> [BrewPackage] {
        var seen = Set<HomebrewPackageID>()
        var candidates: [BrewPackage] = []
        for term in terms {
            try Task.checkCancellation()
            for package in try await catalogue.searchPackages(matching: term, limit: Self.resultsPerTerm)
                where seen.insert(package.id).inserted
            {
                candidates.append(package)
            }
        }
        return Array(candidates.prefix(Self.maximumCandidates))
    }

    static func normalisedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(maximumSearchTerms)
            .map(\.self)
    }

    static func candidate(for package: BrewPackage) -> SuggestionCandidate {
        let description = package.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = description.count > maximumSummaryLength
            ? String(description.prefix(maximumSummaryLength - 1)) + "…"
            : description
        return SuggestionCandidate(id: package.id, name: package.name, summary: summary)
    }

    static func validated(_ picks: [ModelPick], against candidates: [BrewPackage]) -> [PackageSuggestion] {
        var seen = Set<HomebrewPackageID>()
        var suggestions: [PackageSuggestion] = []
        for pick in picks {
            let name = pick.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let package = candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  seen.insert(package.id).inserted
            else {
                continue
            }
            let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            suggestions.append(PackageSuggestion(package: package, reason: reason))
            if suggestions.count == maximumSuggestions {
                break
            }
        }
        return suggestions
    }
}
