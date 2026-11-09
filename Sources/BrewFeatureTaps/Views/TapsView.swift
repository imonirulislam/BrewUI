//
//  TapsView.swift
//  BrewFeatureTaps
//

import BrewAppEnvironment
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import SwiftUI

public extension EnvironmentValues {
    /// Injected by the composition root; the default lists nothing so previews never run brew.
    @Entry var tapsRepository: any TapsRepository = EmptyTapsRepository()
}

final class EmptyTapsRepository: TapsRepository {
    var state: LoadState<[BrewTap], any Error> {
        .loaded([])
    }

    func load(forceRefresh _: Bool) async {}
}

public struct TapsRoot: View {
    @Environment(\.tapsRepository) private var repository
    @Environment(\.installedPackagesRepository) private var installedRepository
    @Environment(\.brewCommandCenter) private var brewCommandCenter

    public init() {}

    public var body: some View {
        TapsView(viewModel: TapsViewModel(
            repository: repository,
            installedRepository: installedRepository,
            brewCommandCenter: brewCommandCenter,
        ))
    }
}

struct TapsView: View {
    @State private var viewModel: TapsViewModel

    init(viewModel: TapsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                addTapField
                Divider()
                AsyncContentView(
                    state: viewModel.state,
                    onRetry: { Task { await viewModel.refresh() } },
                    loaded: { content in tapList(content.taps) },
                )
            }
            .frame(minWidth: BrewLayout.installedListColumnMinWidth, idealWidth: BrewLayout.installedListColumnIdealWidth,
                   maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ScrollView {
                if let tap = viewModel.selectedTap {
                    TapDetailView(tap: tap, viewModel: viewModel)
                        .padding(BrewSpacing.xl)
                        .brewPaneContentWidth()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { viewModel.pendingAction != nil }, set: { if !$0 { viewModel.pendingAction = nil } }),
            presenting: viewModel.pendingAction,
        ) { action in
            Button(confirmButtonTitle(for: action), role: action.isRemoval ? .destructive : nil) {
                Task { await viewModel.confirmPendingAction() }
            }
            Button(String(localized: "Cancel", bundle: #bundle, comment: "Taps: cancel a tap or untap"), role: .cancel) {}
        } message: { action in
            Text(confirmationMessage(for: action))
        }
    }

    private var addTapField: some View {
        HStack(spacing: BrewSpacing.sm) {
            TextField(String(localized: "user/repo", bundle: #bundle, comment: "Taps: placeholder for a new tap name"),
                      text: $viewModel.newTapName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.requestAdd() }
            Button {
                viewModel.requestAdd()
            } label: {
                if viewModel.runningAction != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Add Tap…", bundle: #bundle, comment: "Taps: add a tap after confirmation")
                }
            }
            .disabled(!viewModel.canAddTap)
        }
        .padding(BrewSpacing.lg)
    }

    private func tapList(_ taps: [BrewTap]) -> some View {
        List(taps) { tap in
            HStack(spacing: BrewSpacing.sm) {
                VStack(alignment: .leading, spacing: BrewSpacing.xxs) {
                    Text(tap.name)
                        .font(.brewBodyEmphasized)
                    Text(packageCounts(for: tap))
                        .font(.brewCaption)
                        .foregroundStyle(Color.brewTextSecondary)
                }
                Spacer(minLength: 0)
                TapOriginBadge(tap: tap)
            }
            .padding(.vertical, BrewSpacing.xs)
            .contentShape(Rectangle())
            .listRowBackground(
                RoundedRectangle(cornerRadius: BrewRadius.lg, style: .continuous)
                    .fill(viewModel.selectedTap == tap ? Color.brewBrandTint : Color.clear)
                    .padding(.horizontal, BrewSpacing.sm),
            )
            .onTapGesture { viewModel.select(tap) }
            .accessibilityAddTraits(viewModel.selectedTap == tap ? [.isSelected, .isButton] : [.isButton])
        }
        .listStyle(.inset)
    }

    private func packageCounts(for tap: BrewTap) -> String {
        // In API mode brew lists nothing locally for its own taps, so a count would read as empty.
        if tap.isOfficial, tap.formulaNames.isEmpty, tap.caskTokens.isEmpty {
            return String(localized: "Maintained by Homebrew", bundle: #bundle,
                          comment: "Taps: row subtitle for an official tap whose packages brew does not list locally")
        }
        let formulae = tap.formulaNames.count == 1
            ? String(localized: "1 formula", bundle: #bundle, comment: "Taps: row subtitle part, one formula")
            : String(localized: "\(tap.formulaNames.count) formulae", bundle: #bundle,
                     comment: "Taps: row subtitle part; %lld formulae")
        let casks = tap.caskTokens.count == 1
            ? String(localized: "1 cask", bundle: #bundle, comment: "Taps: row subtitle part, one cask")
            : String(localized: "\(tap.caskTokens.count) casks", bundle: #bundle, comment: "Taps: row subtitle part; %lld casks")
        return String(localized: "\(formulae), \(casks)", bundle: #bundle,
                      comment: "Taps: row subtitle; %1$@ is the formula count, %2$@ the cask count")
    }

    private var confirmationTitle: String {
        switch viewModel.pendingAction {
        case let .add(name):
            String(localized: "Add the tap \(name)?", bundle: #bundle, comment: "Taps: add confirmation title; %@ is the tap")
        case let .remove(tap):
            String(localized: "Remove the tap \(tap.name)?", bundle: #bundle, comment: "Taps: remove confirmation title; %@ is the tap")
        case nil:
            ""
        }
    }

    private func confirmButtonTitle(for action: TapAction) -> String {
        action.isRemoval
            ? String(localized: "Remove Tap", bundle: #bundle, comment: "Taps: confirm untap")
            : String(localized: "Add Tap", bundle: #bundle, comment: "Taps: confirm tap")
    }

    private func confirmationMessage(for action: TapAction) -> String {
        let command = action.command.displayCommand
        if action.isRemoval {
            return String(localized: "Brewly will run: \(command)", bundle: #bundle,
                          comment: "Taps: untap confirmation; %@ is the exact command")
        }
        return String(
            localized: "Brewly will run: \(command)\n\nThird-party taps are maintained by their authors, not Homebrew. Packages you install from them run their code on your Mac.",
            bundle: #bundle,
            comment: "Taps: tap confirmation with a third-party warning; %@ is the exact command",
        )
    }
}

private extension TapAction {
    var isRemoval: Bool {
        if case .remove = self {
            return true
        }
        return false
    }
}

private struct TapOriginBadge: View {
    let tap: BrewTap

    var body: some View {
        Text(tap.isOfficial
            ? String(localized: "Official", bundle: #bundle, comment: "Taps: badge for a Homebrew-maintained tap")
            : String(localized: "Third-party", bundle: #bundle, comment: "Taps: badge for a tap not maintained by Homebrew"))
            .font(.brewCaption2.weight(.semibold))
            .foregroundStyle(tap.isOfficial ? Color.brewTextBrand : Color.brewTextSecondary)
            .padding(.horizontal, BrewSpacing.xs)
            .padding(.vertical, BrewSpacing.xxs)
            .background(Capsule().strokeBorder(Color.brewTextTertiary.opacity(0.5)))
    }
}

private struct TapDetailView: View {
    let tap: BrewTap
    let viewModel: TapsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: BrewSpacing.sm) {
                Text(tap.name).font(.brewTitle2)
                TapOriginBadge(tap: tap)
            }
            if let remote = tap.remote {
                Link(remote.absoluteString, destination: remote)
                    .font(.brewCallout)
            }
            if let lastCommit = tap.lastCommit {
                Text("Last updated \(lastCommit)", bundle: #bundle, comment: "Taps: age of the tap's latest commit; %@ is e.g. 2 days ago")
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewTextSecondary)
            }

            if let error = viewModel.actionError {
                Text(error)
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewStatusError)
                    .textSelection(.enabled)
            }

            section(title: String(localized: "Installed from this tap", bundle: #bundle, comment: "Taps: heading for installed packages")) {
                let installed = viewModel.installedPackages(from: tap)
                if installed.isEmpty {
                    Text("Nothing installed from this tap.", bundle: #bundle, comment: "Taps: no installed packages from the tap")
                        .foregroundStyle(Color.brewTextSecondary)
                } else {
                    ForEach(installed) { package in
                        Text(verbatim: package.name)
                    }
                }
            }

            section(title: String(localized: "Available", bundle: #bundle, comment: "Taps: heading for everything the tap provides")) {
                Text(names(for: tap))
                    .font(.brewCodeSmall)
                    .foregroundStyle(Color.brewTextSecondary)
                    .textSelection(.enabled)
            }

            removeSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var removeSection: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.sm) {
            CommandBlockView(command: BrewCommands.untap(name: tap.name).displayCommand)
            Button(role: .destructive) {
                viewModel.requestRemove(tap)
            } label: {
                Text("Remove Tap…", bundle: #bundle, comment: "Taps: remove a tap after confirmation")
            }
            .disabled(viewModel.removalBlockReason(for: tap) != nil || viewModel.runningAction != nil)
            if let reason = viewModel.removalBlockReason(for: tap) {
                Text(reason)
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewTextSecondary)
            }
        }
    }

    private func names(for tap: BrewTap) -> String {
        let all = tap.formulaNames + tap.caskTokens
        guard !all.isEmpty else {
            return String(localized: "Nothing listed.", bundle: #bundle, comment: "Taps: tap provides no formulae or casks")
        }
        return all.sorted().joined(separator: ", ")
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: BrewSpacing.xs) {
            Text(title).font(.brewBodyEmphasized)
            content()
        }
    }
}
