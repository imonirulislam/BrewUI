//
//  PackageSuggestionModel.swift
//  BrewAssistantCore
//

import BrewCore
import Foundation

public enum AssistantAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// A cloud provider is chosen but its model, address or API key is missing.
    case needsConfiguration
    case unavailable
}

public enum AssistantError: Error, Equatable, Sendable {
    case unavailable(AssistantAvailability)
    case contextWindowExceeded
    case guardrailViolation
    case refusal
    case unsupportedLanguage
    case rateLimited
    /// The provider rejected the API key.
    case unauthorized
    case generationFailed(String)
}

/// A catalogue package as the model sees it: real identity plus a summary short enough for a small context.
public struct SuggestionCandidate: Equatable, Sendable {
    public let id: HomebrewPackageID
    public let name: String
    public let summary: String

    public init(id: HomebrewPackageID, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// The model's raw choice. Untrusted: `name` only counts if it matches a candidate the app offered.
public struct ModelPick: Decodable, Equatable, Sendable {
    public let name: String
    public let reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct PackageSuggestion: Equatable, Identifiable, Sendable {
    public let package: BrewPackage
    public let reason: String

    public var id: HomebrewPackageID {
        package.id
    }

    public init(package: BrewPackage, reason: String) {
        self.package = package
        self.reason = reason
    }
}

public protocol PackageSuggestionModel: Sendable {
    var availability: AssistantAvailability { get }
    /// Likely package names or short search terms for a plain-language request.
    func searchTerms(for request: String) async throws -> [String]
    func choose(for request: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick]
}
