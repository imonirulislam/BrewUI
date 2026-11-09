//
//  AssistantEnvironment.swift
//  BrewFeatureAssistant
//

import BrewAssistantCore
import SwiftUI

public extension EnvironmentValues {
    /// Injected by the composition root; the default reports itself unavailable so previews never reach a model.
    @Entry var packageSuggestionModel: any PackageSuggestionModel = UnavailablePackageSuggestionModel()
}

public struct UnavailablePackageSuggestionModel: PackageSuggestionModel {
    public init() {}

    public var availability: AssistantAvailability {
        .unavailable
    }

    public func searchTerms(for _: String) async throws -> [String] {
        throw AssistantError.unavailable(.unavailable)
    }

    public func choose(for _: String, from _: [SuggestionCandidate]) async throws -> [ModelPick] {
        throw AssistantError.unavailable(.unavailable)
    }
}
