//
//  AssistantViewModel.swift
//  BrewFeatureAssistant
//

import BrewAssistantCore
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import Foundation
import Observation

enum AssistantState: Equatable {
    case idle
    case thinking
    case results([PackageSuggestion])
    case noMatches
    case failed(String)
}

@Observable
@MainActor
final class AssistantViewModel {
    var request = ""
    private(set) var state: AssistantState = .idle
    private(set) var availability: AssistantAvailability
    private(set) var installing: Set<HomebrewPackageID> = []
    private(set) var installErrors: [HomebrewPackageID: String] = [:]
    var pendingInstall: PackageSuggestion?

    @ObservationIgnored private let model: any PackageSuggestionModel
    @ObservationIgnored private let pipeline: SuggestionPipeline
    @ObservationIgnored private let installedRepository: any InstalledPackageStatusReading
    @ObservationIgnored private let brewCommandCenter: any BrewCommandCenter
    @ObservationIgnored private let commandFactory: any BrewMutatingCommandFactory
    @ObservationIgnored private var requestTask: Task<Void, Never>?

    init(
        model: any PackageSuggestionModel,
        catalogue: any CatalogueRepository,
        installedRepository: any InstalledPackageStatusReading,
        brewCommandCenter: any BrewCommandCenter,
        commandFactory: any BrewMutatingCommandFactory,
    ) {
        self.model = model
        pipeline = SuggestionPipeline(model: model, catalogue: catalogue)
        self.installedRepository = installedRepository
        self.brewCommandCenter = brewCommandCenter
        self.commandFactory = commandFactory
        availability = model.availability
    }

    var canSubmit: Bool {
        availability == .available && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshAvailability() {
        availability = model.availability
    }

    func submit() {
        refreshAvailability()
        guard canSubmit else {
            return
        }
        let request = request
        requestTask?.cancel()
        state = .thinking
        requestTask = Task { [weak self, pipeline] in
            do {
                let suggestions = try await pipeline.suggestions(for: request)
                guard !Task.isCancelled else {
                    return
                }
                self?.state = suggestions.isEmpty ? .noMatches : .results(suggestions)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.state = .failed(AssistantCopy.message(for: error))
            }
        }
    }

    func isInstalled(_ suggestion: PackageSuggestion) -> Bool {
        installedRepository.isInstalled(suggestion.id)
    }

    func installCommand(for suggestion: PackageSuggestion) -> String {
        switch suggestion.package.kind {
        case .formula:
            "brew install \(suggestion.package.name)"
        case .cask:
            "brew install --cask \(suggestion.package.name)"
        }
    }

    func requestInstall(_ suggestion: PackageSuggestion) {
        guard !installing.contains(suggestion.id), !isInstalled(suggestion) else {
            return
        }
        pendingInstall = suggestion
    }

    func confirmInstall() {
        guard let suggestion = pendingInstall else {
            return
        }
        pendingInstall = nil
        let package = suggestion.package
        let operationID = BrewOperationID(kind: package.kind, name: package.name)
        let command = commandFactory.installCommand(kind: package.kind, name: package.name)
        installing.insert(suggestion.id)
        installErrors[suggestion.id] = nil
        Task { [weak self, brewCommandCenter] in
            do {
                try await brewCommandCenter.perform(command, id: operationID)
            } catch {
                let phase = await brewCommandCenter.phase(for: operationID)
                let message = if case let .failed(reason: failure) = phase {
                    BrewErrorCopy.message(for: failure)
                } else {
                    BrewErrorCopy.message(for: error, fallback: AssistantCopy.installFailed)
                }
                self?.installErrors[suggestion.id] = message
            }
            self?.installing.remove(suggestion.id)
        }
    }
}
