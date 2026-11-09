//
//  TapsViewModel.swift
//  BrewFeatureTaps
//

import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import Foundation
import Observation

enum TapAction: Equatable, Identifiable {
    case add(String)
    case remove(BrewTap)

    var id: String {
        command.displayCommand
    }

    var command: BrewCommand {
        switch self {
        case let .add(name):
            BrewCommands.tap(name: name)
        case let .remove(tap):
            BrewCommands.untap(name: tap.name)
        }
    }
}

@Observable
@MainActor
final class TapsViewModel {
    var newTapName = ""
    var pendingAction: TapAction?
    private(set) var runningAction: TapAction?
    private(set) var actionError: String?
    private var selectedTapName: String?

    @ObservationIgnored private let repository: any TapsRepository
    @ObservationIgnored private let installedRepository: any InstalledInventoryObserving
    @ObservationIgnored private let brewCommandCenter: any BrewCommandCenter

    init(
        repository: any TapsRepository,
        installedRepository: any InstalledInventoryObserving,
        brewCommandCenter: any BrewCommandCenter,
    ) {
        self.repository = repository
        self.installedRepository = installedRepository
        self.brewCommandCenter = brewCommandCenter
    }

    var state: LoadState<TapListContent, String> {
        switch repository.state {
        case .loading:
            .loading
        case let .loaded(taps):
            .loaded(TapListContent(taps: taps))
        case let .failed(error):
            .failed(BrewErrorCopy.message(for: error, fallback: TapsCopy.loadFailed))
        }
    }

    private var taps: [BrewTap] {
        repository.state.value ?? []
    }

    var selectedTap: BrewTap? {
        taps.first { $0.name == selectedTapName } ?? taps.first
    }

    func select(_ tap: BrewTap) {
        selectedTapName = tap.name
    }

    func load() async {
        await repository.load(forceRefresh: false)
    }

    func refresh() async {
        await repository.load(forceRefresh: true)
    }

    func installedPackages(from tap: BrewTap) -> [InstalledBrewPackage] {
        installedRepository.userManagedPackages
            .filter { $0.tap?.caseInsensitiveCompare(tap.name) == .orderedSame }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var trimmedNewTapName: String {
        newTapName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canAddTap: Bool {
        let name = trimmedNewTapName
        return BrewTap.isValidName(name)
            && !taps.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            && runningAction == nil
    }

    func removalBlockReason(for tap: BrewTap) -> String? {
        if tap.isOfficial {
            return TapsCopy.officialTapCannotBeRemoved
        }
        let installed = installedPackages(from: tap).count
        guard installed == 0 else {
            return TapsCopy.tapHasInstalledPackages(count: installed)
        }
        return nil
    }

    func requestAdd() {
        guard canAddTap else {
            return
        }
        pendingAction = .add(trimmedNewTapName)
    }

    func requestRemove(_ tap: BrewTap) {
        guard removalBlockReason(for: tap) == nil, runningAction == nil else {
            return
        }
        pendingAction = .remove(tap)
    }

    func confirmPendingAction() async {
        guard let action = pendingAction else {
            return
        }
        pendingAction = nil
        runningAction = action
        actionError = nil
        defer { runningAction = nil }

        let command = action.command
        do {
            try await brewCommandCenter.perform(command, id: .tapManagement(command))
        } catch {
            actionError = BrewErrorCopy.message(for: error, fallback: TapsCopy.actionFailed(command.displayCommand))
            return
        }
        if case let .add(name) = action {
            newTapName = ""
            selectedTapName = name
        }
        await repository.load(forceRefresh: true)
    }
}

struct TapListContent: Placeholdable {
    let taps: [BrewTap]

    static var placeholder: TapListContent {
        TapListContent(taps: (0 ..< 6).map { index in
            BrewTap(name: "placeholder/tap\(index)", remote: nil, isOfficial: false, isTrusted: false, isPrivate: false,
                    formulaNames: ["placeholder"], caskTokens: [], lastCommit: nil)
        })
    }
}

enum TapsCopy {
    static var loadFailed: String {
        String(localized: "Couldn’t list your taps.", bundle: #bundle, comment: "Taps: brew tap-info failed")
    }

    static var officialTapCannotBeRemoved: String {
        String(localized: "Official Homebrew taps can’t be removed here.", bundle: #bundle,
               comment: "Taps: why Remove is unavailable for an official tap")
    }

    static func tapHasInstalledPackages(count: Int) -> String {
        if count == 1 {
            return String(localized: "Uninstall the 1 package from this tap before removing it.", bundle: #bundle,
                          comment: "Taps: why Remove is unavailable; one package installed from the tap")
        }
        return String(localized: "Uninstall the \(count) packages from this tap before removing it.", bundle: #bundle,
                      comment: "Taps: why Remove is unavailable; %lld packages installed from the tap")
    }

    static func actionFailed(_ command: String) -> String {
        String(localized: "\(command) failed.", bundle: #bundle, comment: "Taps: a tap or untap command failed; %@ is the command")
    }
}
