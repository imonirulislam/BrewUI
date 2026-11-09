//
//  AssistantView.swift
//  BrewFeatureAssistant
//

import AppKit
import BrewAccessibilityID
import BrewAppEnvironment
import BrewAssistantCore
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import SwiftUI

public struct AssistantRoot: View {
    @Environment(\.packageSuggestionModel) private var model
    @Environment(\.catalogueRepository) private var catalogue
    @Environment(\.installedPackagesRepository) private var installedRepository
    @Environment(\.brewCommandCenter) private var brewCommandCenter
    @Environment(\.mutatingCommandFactory) private var commandFactory

    public init() {}

    public var body: some View {
        AssistantView(viewModel: AssistantViewModel(
            model: model,
            catalogue: catalogue,
            installedRepository: installedRepository,
            brewCommandCenter: brewCommandCenter,
            commandFactory: commandFactory,
        ))
    }
}

struct AssistantView: View {
    @State private var viewModel: AssistantViewModel
    @FocusState private var requestFieldIsFocused: Bool

    init(viewModel: AssistantViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrewSpacing.xl) {
                header
                if viewModel.availability != .available {
                    AssistantUnavailableNotice(availability: viewModel.availability)
                }
                requestField
                content
            }
            .padding(BrewSpacing.xl)
            .brewPaneContentWidth()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.brewWindowBase)
        .accessibilityElement(children: .contain)
        .axid(.assistantScreen)
        .onAppear {
            viewModel.refreshAvailability()
            requestFieldIsFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshAvailability()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { viewModel.pendingInstall != nil },
                set: { if !$0 { viewModel.pendingInstall = nil } },
            ),
            presenting: viewModel.pendingInstall,
        ) { _ in
            Button(String(localized: "Install", bundle: #bundle, comment: "Assistant: confirm install button")) {
                viewModel.confirmInstall()
            }
            Button(String(localized: "Cancel", bundle: #bundle, comment: "Assistant: cancel install button"), role: .cancel) {}
        } message: { suggestion in
            Text("Brewly will run: \(viewModel.installCommand(for: suggestion))", bundle: #bundle,
                 comment: "Assistant: install confirmation; %@ is the exact brew command")
        }
    }

    private var confirmationTitle: String {
        guard let suggestion = viewModel.pendingInstall else {
            return ""
        }
        return String(localized: "Install \(suggestion.package.displayName)?", bundle: #bundle,
                      comment: "Assistant: install confirmation title; %@ is the package name")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.xs) {
            Text("Find software by describing what you need", bundle: #bundle, comment: "Assistant: page heading")
                .font(.brewTitle2)
            Text(
                """
                Apple’s on-device model suggests packages, and Brewly checks each one against the Homebrew \
                catalogue. Nothing leaves your Mac and nothing installs until you confirm.
                """,
                bundle: #bundle,
                comment: "Assistant: explanation under the heading",
            )
            .font(.brewCallout)
            .foregroundStyle(Color.brewTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var requestField: some View {
        HStack(spacing: BrewSpacing.sm) {
            TextField(
                String(localized: "For example: something to convert videos", bundle: #bundle,
                       comment: "Assistant: request field placeholder"),
                text: $viewModel.request,
            )
            .textFieldStyle(.roundedBorder)
            .focused($requestFieldIsFocused)
            .onSubmit { viewModel.submit() }
            .disabled(viewModel.availability != .available)

            Button {
                viewModel.submit()
            } label: {
                Text("Suggest", bundle: #bundle, comment: "Assistant: submit request button")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit || viewModel.state == .thinking)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .thinking:
            HStack(spacing: BrewSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Searching the catalogue…", bundle: #bundle, comment: "Assistant: working on a request")
                    .foregroundStyle(Color.brewTextSecondary)
            }
        case .noMatches:
            NoteCallout(LocalizedStringResource(
                "No matching packages found in the Homebrew catalogue. Try naming the kind of tool or a related app.",
                bundle: #bundle,
                comment: "Assistant: no catalogue matches for the request",
            ), tone: .info)
        case let .failed(message):
            Text(message)
                .font(.brewCallout)
                .foregroundStyle(Color.brewStatusError)
                .textSelection(.enabled)
        case let .results(suggestions):
            VStack(alignment: .leading, spacing: BrewSpacing.md) {
                ForEach(suggestions) { suggestion in
                    AssistantSuggestionRow(suggestion: suggestion, viewModel: viewModel)
                }
            }
        }
    }
}

private struct AssistantUnavailableNotice: View {
    let availability: AssistantAvailability
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.sm) {
            NoteCallout(verbatim: AssistantCopy.unavailableTitle(for: availability))
            if availability == .appleIntelligenceNotEnabled {
                Button {
                    openURL(Self.appleIntelligenceSettingsURL)
                } label: {
                    Text("Open Apple Intelligence Settings…", bundle: #bundle,
                         comment: "Assistant: button opening System Settings")
                }
            }
        }
    }

    private static let appleIntelligenceSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
}

private struct AssistantSuggestionRow: View {
    let suggestion: PackageSuggestion
    let viewModel: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: BrewSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrewSpacing.sm) {
                Text(suggestion.package.displayName)
                    .font(.brewTitle3)
                Text(suggestion.package.kind.chrome.badgeLabel)
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewTextSecondary)
                Spacer(minLength: 0)
                installControl
            }
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .font(.brewBody)
            }
            if !suggestion.package.description.isEmpty {
                Text(suggestion.package.description)
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewTextSecondary)
            }
            CommandBlockView(command: viewModel.installCommand(for: suggestion))
            if let error = viewModel.installErrors[suggestion.id] {
                Text(error)
                    .font(.brewCallout)
                    .foregroundStyle(Color.brewStatusError)
                    .textSelection(.enabled)
            }
        }
        .padding(BrewSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: BrewRadius.md)
                .fill(Color.brewSurfaceElevated)
        }
    }

    @ViewBuilder
    private var installControl: some View {
        if viewModel.isInstalled(suggestion) {
            Text("Installed", bundle: #bundle, comment: "Assistant: package already installed")
                .font(.brewCallout)
                .foregroundStyle(Color.brewTextSecondary)
        } else if viewModel.installing.contains(suggestion.id) {
            ProgressView().controlSize(.small)
        } else {
            Button {
                viewModel.requestInstall(suggestion)
            } label: {
                Text("Install…", bundle: #bundle, comment: "Assistant: install button that asks for confirmation")
            }
        }
    }
}
