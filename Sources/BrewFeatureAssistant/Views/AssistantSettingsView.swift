//
//  AssistantSettingsView.swift
//  BrewFeatureAssistant
//

import BrewAccessibilityID
import BrewAssistantCore
import BrewUIComponents
import SwiftUI

public extension EnvironmentValues {
    /// Injected by the composition root with the Keychain store; the default keeps nothing.
    @Entry var assistantCredentialStore: any AssistantCredentialStoring = NoCredentialStore()

    /// Selects the Assistant tab before Settings opens; the app shell owns the Settings window.
    @Entry var selectAssistantSettingsTab: @MainActor @Sendable () -> Void = {}
}

public struct NoCredentialStore: AssistantCredentialStoring {
    public init() {}

    public func apiKey(for _: AssistantProvider) -> String? {
        nil
    }

    public func setAPIKey(_: String?, for _: AssistantProvider) throws {}
}

enum AssistantProviderCopy {
    static func name(for provider: AssistantProvider) -> String {
        switch provider {
        case .onDevice:
            String(localized: "On this Mac (Apple Intelligence)", bundle: #bundle, comment: "Assistant provider: Apple's on-device model")
        case .anthropic:
            String(localized: "Claude (Anthropic)", bundle: #bundle, comment: "Assistant provider: Anthropic's Claude API")
        case .openAI:
            String(localized: "OpenAI (ChatGPT and Codex models)", bundle: #bundle, comment: "Assistant provider: OpenAI's API")
        case .openAICompatible:
            String(localized: "OpenAI-compatible server (Ollama, LM Studio…)", bundle: #bundle,
                   comment: "Assistant provider: any server speaking the OpenAI chat completions API")
        }
    }

    /// Says exactly what leaves the Mac and where it goes; shown on the Assistant page and in Settings.
    static func privacyNote(for provider: AssistantProvider, baseURL: String) -> String {
        switch provider {
        case .onDevice:
            return String(
                localized: """
                Apple’s on-device model suggests packages, and Brewly checks each one against the Homebrew \
                catalogue. Nothing leaves your Mac and nothing installs until you confirm.
                """,
                bundle: #bundle,
                comment: "Assistant: explanation under the heading",
            )
        case .anthropic, .openAI:
            let destination = provider == .anthropic ? "Anthropic" : "OpenAI"
            return String(
                localized: """
                Brewly sends your request and the names and descriptions of matching catalogue packages to \
                \(destination), then checks every suggestion against the Homebrew catalogue. Nothing installs \
                until you confirm.
                """,
                bundle: #bundle,
                comment: "Assistant: privacy note for a cloud provider; %@ is Anthropic or OpenAI",
            )
        case .openAICompatible:
            let host = URL(string: baseURL)?.host ?? baseURL
            return String(
                localized: """
                Brewly sends your request and the names and descriptions of matching catalogue packages to \
                \(host), then checks every suggestion against the Homebrew catalogue. Nothing installs until \
                you confirm.
                """,
                bundle: #bundle,
                comment: "Assistant: privacy note for an OpenAI-compatible server; %@ is the server's host name",
            )
        }
    }
}

public struct AssistantSettingsView: View {
    @Environment(\.assistantCredentialStore) private var credentials
    @State private var settings = AssistantSettings(defaults: .standard)
    @State private var keyDraft = ""
    @State private var hasSavedKey = false
    @State private var keychainError: String?

    public init() {}

    public var body: some View {
        Form {
            Picker(selection: $settings.provider) {
                ForEach(AssistantProvider.allCases) { provider in
                    Text(verbatim: AssistantProviderCopy.name(for: provider)).tag(provider)
                }
            } label: {
                Text("Model provider", bundle: #bundle, comment: "Assistant settings: provider picker")
            }
            .axid(.assistantProviderPicker)

            if settings.provider != .onDevice {
                TextField(text: $settings.model, prompt: Text(verbatim: settings.provider.defaultModel ?? "")) {
                    Text("Model", bundle: #bundle, comment: "Assistant settings: model identifier field")
                }
                if settings.provider == .openAICompatible {
                    TextField(text: $settings.baseURL, prompt: Text(verbatim: "http://localhost:11434/v1")) {
                        Text("Server address", bundle: #bundle, comment: "Assistant settings: OpenAI-compatible base URL field")
                    }
                }
                apiKeyRow
            }

            Text(AssistantProviderCopy.privacyNote(for: settings.provider, baseURL: settings.baseURL))
                .font(.brewCaption)
                .foregroundStyle(Color.brewTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let keychainError {
                Text(keychainError)
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewStatusError)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: reloadKeyState)
        .onChange(of: settings.provider) { _, provider in
            settings.model = AssistantSettings.model(for: provider, in: .standard)
            reloadKeyState()
        }
        .onChange(of: settings) { _, settings in
            settings.save(to: .standard)
        }
    }

    private var apiKeyRow: some View {
        LabeledContent {
            HStack {
                SecureField(text: $keyDraft, prompt: savedKeyPrompt) {
                    EmptyView()
                }
                Button {
                    store(keyDraft)
                } label: {
                    Text("Save", bundle: #bundle, comment: "Assistant settings: store the API key in the Keychain")
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasSavedKey {
                    Button(role: .destructive) {
                        store(nil)
                    } label: {
                        Text("Remove", bundle: #bundle, comment: "Assistant settings: delete the stored API key")
                    }
                }
            }
        } label: {
            if settings.provider.requiresAPIKey {
                Text("API key", bundle: #bundle, comment: "Assistant settings: API key field")
            } else {
                Text("API key (optional)", bundle: #bundle, comment: "Assistant settings: API key field for servers that may not need one")
            }
        }
    }

    private var savedKeyPrompt: Text? {
        hasSavedKey
            ? Text("Saved in your Keychain", bundle: #bundle, comment: "Assistant settings: API key placeholder when a key is stored")
            : nil
    }

    private func reloadKeyState() {
        keyDraft = ""
        keychainError = nil
        hasSavedKey = !(credentials.apiKey(for: settings.provider) ?? "").isEmpty
    }

    private func store(_ key: String?) {
        do {
            try credentials.setAPIKey(key, for: settings.provider)
            reloadKeyState()
            // The Assistant page watches defaults; touching the provider tells it a key changed.
            settings.save(to: .standard)
        } catch {
            keychainError = String(localized: "Brewly couldn’t update the Keychain: \(error.localizedDescription)", bundle: #bundle,
                                   comment: "Assistant settings: Keychain write failed; %@ is the error")
        }
    }
}
