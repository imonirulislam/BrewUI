//
//  TapsRepository.swift
//  BrewRepositoryInterfaces
//

import BrewCore
import Foundation

@MainActor
public protocol TapsRepository: Sendable {
    var state: LoadState<[BrewTap], any Error> { get }

    /// Cache-first; a forced load keeps the current list on screen until the refetch succeeds.
    func load(forceRefresh: Bool) async
}
