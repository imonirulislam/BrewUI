//
//  AnthropicPackageSuggestionModel.swift
//  BrewAssistantCloud
//

import BrewAssistantCore
import Foundation

/// Claude through the Messages API over plain HTTPS; there is no official Swift SDK. Each answer is a JSON
/// object constrained by `output_config.format`, so nothing is parsed out of free text.
public struct AnthropicPackageSuggestionModel: PackageSuggestionModel {
    static let apiVersion = "2026-10-21"
    /// `fallbacks: "default"` lets the API re-run a declined request on Anthropic's recommended fallback model.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Both questions are short classification work; low effort keeps them quick and cheap.
    static let effort = "low"
    static let maxTokens = 16000

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(apiKey: String, model: String, baseURL: URL, transport: any HTTPTransport = URLSession.shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public var availability: AssistantAvailability {
        apiKey.isEmpty || model.isEmpty ? .needsConfiguration : .available
    }

    public func searchTerms(for request: String) async throws -> [String] {
        let text = try await respond(
            system: AssistantPrompts.planningInstructions,
            prompt: request,
            schemaJSON: AssistantPrompts.planningSchemaJSON,
        )
        return try CloudRequest.decode(AssistantPrompts.SearchPlan.self, fromJSONText: text, provider: "Claude").terms
    }

    public func choose(for request: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick] {
        let text = try await respond(
            system: AssistantPrompts.choosingInstructions,
            prompt: AssistantPrompts.choosingPrompt(request: request, candidates: candidates),
            schemaJSON: AssistantPrompts.choosingSchemaJSON,
        )
        return try CloudRequest.decode(AssistantPrompts.Choice.self, fromJSONText: text, provider: "Claude")
            .picks
    }

    func makeRequest(system: String, prompt: String, schemaJSON: String) throws -> URLRequest {
        let body: [String: Any] = try [
            "model": model,
            "max_tokens": Self.maxTokens,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": Self.effort,
                "format": ["type": "json_schema", "schema": CloudRequest.schemaObject(schemaJSON)],
            ],
            "fallbacks": "default",
        ]
        return try CloudRequest.post(
            baseURL.appendingPathComponent("messages"),
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": Self.apiVersion,
                "anthropic-beta": Self.fallbackBeta,
            ],
            body: body,
        )
    }

    private func respond(system: String, prompt: String, schemaJSON: String) async throws -> String {
        guard availability == .available else {
            throw AssistantError.unavailable(.needsConfiguration)
        }
        let request = try makeRequest(system: system, prompt: prompt, schemaJSON: schemaJSON)
        let data = try await CloudRequest.send(request, with: transport, provider: "Claude")
        let message: MessageResponse
        do {
            message = try JSONDecoder().decode(MessageResponse.self, from: data)
        } catch {
            throw AssistantError.generationFailed("Claude returned a response Brewly could not read")
        }
        // Checked before content: a refusal still returns HTTP 200.
        switch message.stopReason {
        case "refusal":
            throw AssistantError.refusal
        case "max_tokens":
            throw AssistantError.contextWindowExceeded
        default:
            break
        }
        guard let text = message.content.first(where: { $0.type == "text" })?.text else {
            throw AssistantError.generationFailed("Claude returned no answer")
        }
        return text
    }
}

/// Only the fields Brewly reads; thinking and other block types are skipped by `type`.
private struct MessageResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    let content: [Block]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
