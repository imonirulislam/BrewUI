//
//  AssistantCopy.swift
//  BrewFeatureAssistant
//

import BrewAssistantCore
import BrewUIComponents
import Foundation

enum AssistantCopy {
    static var installFailed: String {
        String(localized: "Something went wrong while installing this package.", bundle: #bundle,
               comment: "Assistant: generic install error")
    }

    static func message(for error: any Error) -> String {
        guard let error = error as? AssistantError else {
            return BrewErrorCopy.message(
                for: error,
                fallback: String(localized: "The assistant couldn’t answer. Try again.", bundle: #bundle,
                                 comment: "Assistant: generic failure"),
            )
        }
        return switch error {
        case let .unavailable(availability):
            unavailableTitle(for: availability)
        case .contextWindowExceeded:
            String(localized: "That request is too long for the on-device model. Try a shorter description.",
                   bundle: #bundle, comment: "Assistant: request exceeded the model's context window")
        case .guardrailViolation, .refusal:
            String(localized: "The on-device model declined this request. Try describing the task differently.",
                   bundle: #bundle, comment: "Assistant: model refused or hit a safety guardrail")
        case .unsupportedLanguage:
            String(localized: "The on-device model doesn’t support this language yet. Try English.",
                   bundle: #bundle, comment: "Assistant: request language unsupported")
        case .rateLimited:
            String(localized: "The on-device model is busy. Wait a moment and try again.",
                   bundle: #bundle, comment: "Assistant: model rate limited or busy")
        case let .generationFailed(detail):
            String(localized: "The assistant couldn’t answer: \(detail)", bundle: #bundle,
                   comment: "Assistant: generation failed; %@ is the model's error description")
        }
    }

    static func unavailableTitle(for availability: AssistantAvailability) -> String {
        switch availability {
        case .available:
            ""
        case .appleIntelligenceNotEnabled:
            String(localized: "Turn on Apple Intelligence to use the assistant.", bundle: #bundle,
                   comment: "Assistant: Apple Intelligence is switched off")
        case .modelNotReady:
            String(localized: "The on-device model is still downloading. Try again shortly.", bundle: #bundle,
                   comment: "Assistant: model assets not yet downloaded")
        case .deviceNotEligible:
            String(localized: "This Mac doesn’t support Apple Intelligence, so the assistant isn’t available.",
                   bundle: #bundle, comment: "Assistant: hardware cannot run the on-device model")
        case .unavailable:
            String(localized: "The on-device model isn’t available right now.", bundle: #bundle,
                   comment: "Assistant: model unavailable for an unknown reason")
        }
    }
}
