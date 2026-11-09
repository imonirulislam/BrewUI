//
//  OnDevicePackageSuggestionModel.swift
//  BrewIntelligence
//

import BrewAssistantCore
import FoundationModels

/// Apple's on-device model behind ``PackageSuggestionModel``. One session per request: sessions keep a
/// transcript and refuse concurrent requests, and suggestions need no memory of earlier turns.
public struct OnDevicePackageSuggestionModel: PackageSuggestionModel {
    private let model: SystemLanguageModel

    public init() {
        model = .default
    }

    public var availability: AssistantAvailability {
        switch model.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .unavailable
        }
    }

    public func searchTerms(for request: String) async throws -> [String] {
        let session = try makeSession(instructions: Self.planningInstructions)
        let plan = try await respond(session, to: request, generating: SearchPlan.self)
        return plan.terms
    }

    public func choose(for request: String, from candidates: [SuggestionCandidate]) async throws -> [ModelPick] {
        let session = try makeSession(instructions: Self.choosingInstructions)
        let catalogue = candidates
            .map { "- \($0.name) (\($0.id.kind.rawValue)): \($0.summary)" }
            .joined(separator: "\n")
        let prompt = "Request: \(request)\n\nCandidates:\n\(catalogue)"
        let choice = try await respond(session, to: prompt, generating: Choice.self)
        return choice.picks.map { ModelPick(name: $0.name, reason: $0.reason) }
    }

    private func makeSession(instructions: String) throws -> LanguageModelSession {
        let availability = availability
        guard availability == .available else {
            throw AssistantError.unavailable(availability)
        }
        return LanguageModelSession(model: model, instructions: instructions)
    }

    private func respond<Content: Generable>(
        _ session: LanguageModelSession,
        to prompt: String,
        generating type: Content.Type,
    ) async throws -> Content {
        do {
            return try await session.respond(to: prompt, generating: type).content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.assistantError(for: error)
        }
    }

    static func assistantError(for error: LanguageModelSession.GenerationError) -> AssistantError {
        switch error {
        case .exceededContextWindowSize:
            .contextWindowExceeded
        case .guardrailViolation:
            .guardrailViolation
        case .refusal:
            .refusal
        case .unsupportedLanguageOrLocale:
            .unsupportedLanguage
        case .rateLimited, .concurrentRequests:
            .rateLimited
        case .assetsUnavailable:
            .unavailable(.modelNotReady)
        default:
            .generationFailed(error.localizedDescription)
        }
    }

    private static let planningInstructions = """
    You help people find software in Homebrew, the macOS package manager. Given a request, list the \
    Homebrew formula or cask names most likely to satisfy it, such as ffmpeg, imagemagick or visual-studio-code. \
    Prefer exact package names; use a short keyword only when unsure of a name.
    """

    private static let choosingInstructions = """
    You help people choose software from Homebrew, the macOS package manager. Pick the candidates that best \
    satisfy the request, best first. Only use names exactly as listed. For each, give one short sentence \
    explaining how it helps. Pick nothing that does not fit.
    """
}

@Generable
struct SearchPlan {
    @Guide(description: "Likely Homebrew package names or short keywords", .count(1 ... 5))
    var terms: [String]
}

@Generable
struct Choice {
    @Guide(description: "Best matches first; empty if nothing fits", .maximumCount(5))
    var picks: [Pick]
}

@Generable
struct Pick {
    @Guide(description: "A candidate name exactly as listed")
    var name: String
    @Guide(description: "One short sentence on how it meets the request")
    var reason: String
}
