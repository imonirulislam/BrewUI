//
//  CatalogueRepository.swift
//  BrewRepositoryInterfaces
//

import BrewCore
import Foundation

public protocol CatalogueRepository: Sendable {
    func package(for reference: HomebrewPackageID) async throws -> BrewPackage?
    /// Catalogue-wide name search across both formulae and casks, capped at `limit` results.
    func searchPackages(matching query: String, limit: Int) async throws -> [BrewPackage]
    /// Packages whose description contains `keyword` as a whole word, capped at `limit`.
    func searchPackages(describedBy keyword: String, limit: Int) async throws -> [BrewPackage]
}

public extension CatalogueRepository {
    /// Catalogues without descriptions to search answer nothing rather than failing.
    func searchPackages(describedBy _: String, limit _: Int) async throws -> [BrewPackage] {
        []
    }
}
