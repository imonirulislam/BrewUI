//
//  ConfiguredPackageSuggestionModel.swift
//  BrewAssistantCloud
//

import BrewAssistantCore
import Foundation

/// Reads the provider choice on every call, so a change in Settings applies to the next request without
/// rebuilding the Assistant.
public struct ConfiguredPackageSuggestionModel: PackageSuggestionModel {
    private let onDevice: any PackageSuggestionModel
    private let credentials: any AssistantCredentialStoring
    /// A suite name rather than `UserDefaults`, which is not `Sendable`; `nil` is the standard defaults.
    private let defaultsSuiteName: String?
    private let transport: any HTTPTransport

    public init(
        onDevice: any PackageSuggestionModel,
        credentials: any AssistantCredentialStoring,
        defaultsSuiteName: String? = nil,
        transport: any HTTPTransport = URLSession.shared,
    ) {
        self.onDevice = onDevice
        self.credentials = credentials
        self.defaultsSuiteName = defaultsSuiteName
        self.transport = transport
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public var availability: AssistantAvailability {
        let settings = AssistantSettings(defaults: defaults)
        guard settings.provider != .onDevice else {
            return onDevice.availability
        }
        return settings.isConfigured(apiKey: credentials.apiKey(for: settings.provider)) ? .available : .needsConfiguration
    }

    public func searchTerms(for request: String) async throws -> [String] {
        try await current().searchTerms(for: request)
    }

    public func choose(for request: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick] {
        try await current().choose(for: request, from: candidates)
    }

    func current() throws -> any PackageSuggestionModel {
        let settings = AssistantSettings(defaults: defaults)
        let apiKey = credentials.apiKey(for: settings.provider)
        guard settings.isConfigured(apiKey: apiKey) else {
            throw AssistantError.unavailable(.needsConfiguration)
        }
        guard settings.provider != .onDevice else {
            return onDevice
        }
        guard let baseURL = settings.effectiveBaseURL else {
            throw AssistantError.unavailable(.needsConfiguration)
        }
        switch settings.provider {
        case .anthropic:
            return AnthropicPackageSuggestionModel(
                apiKey: apiKey ?? "",
                model: settings.effectiveModel,
                baseURL: baseURL,
                transport: transport,
            )
        case .onDevice, .openAI, .openAICompatible:
            return OpenAICompatiblePackageSuggestionModel(
                apiKey: apiKey,
                model: settings.effectiveModel,
                baseURL: baseURL,
                providerName: settings.provider == .openAI ? "OpenAI" : (baseURL.host ?? "The server"),
                transport: transport,
            )
        }
    }
}
