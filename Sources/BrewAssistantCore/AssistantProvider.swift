//
//  AssistantProvider.swift
//  BrewAssistantCore
//

import Foundation

/// Where the Assistant's model runs. Every provider sits behind ``PackageSuggestionModel``, so the
/// catalogue check and the confirm-before-install path are the same for all of them.
public enum AssistantProvider: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case anthropic
    case openAI
    case openAICompatible

    public var id: String {
        rawValue
    }

    public var sendsRequestsOffDevice: Bool {
        self != .onDevice
    }

    /// Local OpenAI-compatible servers such as Ollama usually take no key.
    public var requiresAPIKey: Bool {
        self == .anthropic || self == .openAI
    }

    public var defaultModel: String? {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .onDevice, .openAI, .openAICompatible: nil
        }
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1")
        case .openAI: URL(string: "https://api.openai.com/v1")
        case .onDevice, .openAICompatible: nil
        }
    }
}

public enum AssistantSettingsKey {
    public static let provider = "assistantProvider"
    public static let modelPrefix = "assistantModel."
    public static let baseURL = "assistantBaseURL"
}

/// The user's provider choice, kept in defaults. API keys live in the Keychain, never here.
public struct AssistantSettings: Equatable, Sendable {
    public var provider: AssistantProvider
    public var model: String
    public var baseURL: String

    public init(provider: AssistantProvider = .onDevice, model: String = "", baseURL: String = "") {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
    }

    /// Each provider remembers its own model, so switching back and forth keeps both choices.
    public init(defaults: UserDefaults) {
        let provider = defaults.string(forKey: AssistantSettingsKey.provider).flatMap(AssistantProvider.init(rawValue:)) ?? .onDevice
        self.init(
            provider: provider,
            model: defaults.string(forKey: AssistantSettingsKey.modelPrefix + provider.rawValue) ?? "",
            baseURL: defaults.string(forKey: AssistantSettingsKey.baseURL) ?? "",
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(provider.rawValue, forKey: AssistantSettingsKey.provider)
        defaults.set(model, forKey: AssistantSettingsKey.modelPrefix + provider.rawValue)
        defaults.set(baseURL, forKey: AssistantSettingsKey.baseURL)
    }

    public static func model(for provider: AssistantProvider, in defaults: UserDefaults) -> String {
        defaults.string(forKey: AssistantSettingsKey.modelPrefix + provider.rawValue) ?? ""
    }

    public var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (provider.defaultModel ?? "") : trimmed
    }

    public var effectiveBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider == .openAICompatible else {
            return provider.defaultBaseURL
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return nil
        }
        return url
    }

    public func isConfigured(apiKey: String?) -> Bool {
        guard provider != .onDevice else {
            return true
        }
        let hasKey = !(apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !effectiveModel.isEmpty && effectiveBaseURL != nil && (hasKey || !provider.requiresAPIKey)
    }
}

/// API keys per provider. The live store is the Keychain; tests use an in-memory one.
public protocol AssistantCredentialStoring: Sendable {
    func apiKey(for provider: AssistantProvider) -> String?
    func setAPIKey(_ key: String?, for provider: AssistantProvider) throws
}
