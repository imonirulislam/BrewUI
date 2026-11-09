//
//  AssistantPrompts.swift
//  BrewAssistantCore
//

import Foundation

/// Instructions, prompts and JSON schemas shared by every provider, so they all answer the same two questions.
public enum AssistantPrompts {
    public static let planningInstructions = """
    You help people find software in Homebrew, the macOS package manager. Given a request, list up to five \
    search terms: the Homebrew formula or cask names most likely to satisfy it, such as ffmpeg, imagemagick or \
    visual-studio-code, and one or two single-word keywords describing what the tool does, such as video or pdf.
    """

    public static let choosingInstructions = """
    You help people choose software from Homebrew, the macOS package manager. Pick the candidates that best \
    satisfy the request, best first. Only use names exactly as listed. For each, give one short sentence \
    explaining how it helps. Pick nothing that does not fit.
    """

    public static func choosingPrompt(request: String, candidates: [SuggestionCandidate]) -> String {
        let catalogue = candidates
            .map { "- \($0.name) (\($0.id.kind.rawValue)): \($0.summary)" }
            .joined(separator: "\n")
        return "Request: \(request)\n\nCandidates:\n\(catalogue)"
    }

    /// `{"terms": [String]}`. Every object closes `additionalProperties` and requires every property, which
    /// both Anthropic and OpenAI strict mode demand.
    public static let planningSchemaJSON = """
    {"type":"object","properties":{"terms":{"type":"array","items":{"type":"string"},\
    "description":"Likely Homebrew package names or single-word keywords"}},\
    "required":["terms"],"additionalProperties":false}
    """

    /// `{"picks": [{"name": String, "reason": String}]}`.
    public static let choosingSchemaJSON = """
    {"type":"object","properties":{"picks":{"type":"array","description":"Best matches first; empty if nothing fits",\
    "items":{"type":"object","properties":{"name":{"type":"string","description":"A candidate name exactly as listed"},\
    "reason":{"type":"string","description":"One short sentence on how it meets the request"}},\
    "required":["name","reason"],"additionalProperties":false}}},\
    "required":["picks"],"additionalProperties":false}
    """

    public struct SearchPlan: Decodable, Sendable {
        public let terms: [String]
    }

    public struct Choice: Decodable, Sendable {
        public let picks: [ModelPick]
    }
}
