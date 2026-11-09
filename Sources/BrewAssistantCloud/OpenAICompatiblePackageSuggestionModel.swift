//
//  OpenAICompatiblePackageSuggestionModel.swift
//  BrewAssistantCloud
//

import BrewAssistantCore
import Foundation

/// The Chat Completions shape with a strict `json_schema` response format. OpenAI, Ollama 0.5+, LM Studio
/// and OpenRouter all accept it, so one client covers ChatGPT, Codex and local models.
public struct OpenAICompatiblePackageSuggestionModel: PackageSuggestionModel {
    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let providerName: String
    private let transport: any HTTPTransport

    public init(
        apiKey: String?,
        model: String,
        baseURL: URL,
        providerName: String,
        transport: any HTTPTransport = URLSession.shared,
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.providerName = providerName
        self.transport = transport
    }

    public var availability: AssistantAvailability {
        model.isEmpty ? .needsConfiguration : .available
    }

    public func searchTerms(for request: String) async throws -> [String] {
        let text = try await respond(
            system: AssistantPrompts.planningInstructions,
            prompt: request,
            schemaName: "search_plan",
            schemaJSON: AssistantPrompts.planningSchemaJSON,
        )
        return try CloudRequest.decode(AssistantPrompts.SearchPlan.self, fromJSONText: text, provider: providerName).terms
    }

    public func choose(for request: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick] {
        let text = try await respond(
            system: AssistantPrompts.choosingInstructions,
            prompt: AssistantPrompts.choosingPrompt(request: request, candidates: candidates),
            schemaName: "choice",
            schemaJSON: AssistantPrompts.choosingSchemaJSON,
        )
        return try CloudRequest.decode(AssistantPrompts.Choice.self, fromJSONText: text, provider: providerName)
            .picks
    }

    func makeRequest(system: String, prompt: String, schemaName: String, schemaJSON: String) throws -> URLRequest {
        let body: [String: Any] = try [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": CloudRequest.schemaObject(schemaJSON)],
            ],
        ]
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return try CloudRequest.post(baseURL.appendingPathComponent("chat/completions"), headers: headers, body: body)
    }

    private func respond(system: String, prompt: String, schemaName: String, schemaJSON: String) async throws -> String {
        guard availability == .available else {
            throw AssistantError.unavailable(.needsConfiguration)
        }
        let request = try makeRequest(system: system, prompt: prompt, schemaName: schemaName, schemaJSON: schemaJSON)
        let data = try await CloudRequest.send(request, with: transport, provider: providerName)
        let completion: ChatCompletion
        do {
            completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        } catch {
            throw AssistantError.generationFailed("\(providerName) returned a response Brewly could not read")
        }
        guard let message = completion.choices.first?.message else {
            throw AssistantError.generationFailed("\(providerName) returned no answer")
        }
        if let refusal = message.refusal, !refusal.isEmpty {
            throw AssistantError.refusal
        }
        if completion.choices.first?.finishReason == "length" {
            throw AssistantError.contextWindowExceeded
        }
        guard let content = message.content, !content.isEmpty else {
            throw AssistantError.generationFailed("\(providerName) returned no answer")
        }
        return content
    }
}

private struct ChatCompletion: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct ChatMessage: Decodable {
    let content: String?
    let refusal: String?
}
