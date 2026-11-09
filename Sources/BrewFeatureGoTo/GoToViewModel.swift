//
//  GoToViewModel.swift
//  BrewFeatureGoTo
//

import BrewCore
import BrewRepositoryInterfaces
import Foundation
import Observation

public struct GoToPage: Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

public enum GoToDestination: Equatable, Sendable {
    case page(String)
    case installedPackage(HomebrewPackageID)
    /// A catalogue package that is not installed; Discover opens searching for it.
    case discover(String)
}

struct GoToResult: Equatable, Identifiable {
    enum Kind: Equatable {
        case page, installed, catalogue
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let systemImage: String
    let destination: GoToDestination

    var id: String {
        "\(kind)-\(title)-\(subtitle ?? "")"
    }
}

@Observable
@MainActor
final class GoToViewModel {
    static let installedLimit = 8
    static let catalogueLimit = 6

    private(set) var results: [GoToResult] = []
    private(set) var highlightedIndex = 0

    @ObservationIgnored private let pages: [GoToPage]
    @ObservationIgnored private let installedRepository: any InstalledInventoryObserving
    @ObservationIgnored private let catalogueRepository: any CatalogueRepository

    init(
        pages: [GoToPage],
        installedRepository: any InstalledInventoryObserving,
        catalogueRepository: any CatalogueRepository,
    ) {
        self.pages = pages
        self.installedRepository = installedRepository
        self.catalogueRepository = catalogueRepository
        results = pages.map(Self.result(for:))
    }

    var highlightedResult: GoToResult? {
        results.indices.contains(highlightedIndex) ? results[highlightedIndex] : nil
    }

    func moveHighlight(by offset: Int) {
        guard !results.isEmpty else {
            return
        }
        highlightedIndex = min(max(highlightedIndex + offset, 0), results.count - 1)
    }

    func highlight(_ result: GoToResult) {
        if let index = results.firstIndex(of: result) {
            highlightedIndex = index
        }
    }

    /// Pages and installed packages answer at once; the catalogue follows when its search returns.
    func search(_ rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        highlightedIndex = 0
        guard !query.isEmpty else {
            results = pages.map(Self.result(for:))
            return
        }

        let pageResults = Self.ranked(pages, by: \.title, query: query).map(Self.result(for:))
        let installed = Self.ranked(installedRepository.userManagedPackages, by: \.name, query: query)
            .prefix(Self.installedLimit)
        let installedResults = installed.map { package in
            GoToResult(kind: .installed, title: package.name, subtitle: package.description,
                       systemImage: package.kind == .cask ? "macwindow" : "terminal",
                       destination: .installedPackage(package.id))
        }
        results = pageResults + installedResults

        let installedIDs = Set(installedRepository.userManagedPackages.map(\.id))
        let catalogue = await (try? catalogueRepository.searchPackages(matching: query, limit: Self.catalogueLimit * 2)) ?? []
        guard !Task.isCancelled else {
            return
        }
        let catalogueResults = Self.ranked(catalogue.filter { !installedIDs.contains($0.id) }, by: \.name, query: query)
            .prefix(Self.catalogueLimit)
            .map { package in
                GoToResult(kind: .catalogue, title: package.name, subtitle: package.description,
                           systemImage: "shippingbox", destination: .discover(package.name))
            }
        results = pageResults + installedResults + catalogueResults
    }

    private static func result(for page: GoToPage) -> GoToResult {
        GoToResult(kind: .page, title: page.title, subtitle: nil, systemImage: page.systemImage, destination: .page(page.id))
    }

    /// Exact, then prefix, then substring matches; alphabetical within each rank.
    private static func ranked<T>(_ items: [T], by name: KeyPath<T, String>, query: String) -> [T] {
        let lowered = query.lowercased()
        func rank(_ item: T) -> Int? {
            let candidate = item[keyPath: name].lowercased()
            if candidate == lowered { return 0 }
            if candidate.hasPrefix(lowered) { return 1 }
            if candidate.contains(lowered) { return 2 }
            return nil
        }
        var matches: [(item: T, rank: Int)] = []
        for item in items {
            if let itemRank = rank(item) {
                matches.append((item, itemRank))
            }
        }
        matches.sort { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            let order: ComparisonResult = lhs.item[keyPath: name].localizedStandardCompare(rhs.item[keyPath: name])
            return order == .orderedAscending
        }
        return matches.map(\.item)
    }
}
