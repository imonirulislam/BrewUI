//
//  MenuBarExtraViews.swift
//  BrewFeatureMenuBar
//

import AppKit
import BrewAppEnvironment
import BrewCore
import BrewRepositoryInterfaces
import BrewUIComponents
import Observation
import SwiftUI

public enum MenuBarPreferenceKey {
    public static let showsMenuBarExtra = "showsMenuBarExtra"
    public static let checksAutomatically = "menuBarChecksAutomatically"
    public static let notifiesAboutUpgrades = "menuBarNotifiesAboutUpgrades"
}

public enum MainWindowDestination: Equatable, Sendable {
    case upgrades
}

/// Lets the menu bar extra ask the main window to show a destination, including one it opens fresh.
@Observable
@MainActor
public final class MainWindowRequests {
    public var pendingDestination: MainWindowDestination?

    public init() {}

    public func consume() -> MainWindowDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}

public extension EnvironmentValues {
    @Entry var mainWindowRequests = MainWindowRequests()
}

/// Icon plus outdated count. Also owns the automatic check, which only runs while the extra is shown.
public struct MenuBarExtraLabel: View {
    @Environment(\.installedPackagesRepository) private var repository
    @AppStorage(MenuBarPreferenceKey.checksAutomatically) private var checksAutomatically = true
    @AppStorage(MenuBarPreferenceKey.notifiesAboutUpgrades) private var notifiesAboutUpgrades = false
    @State private var notifier = UpgradeNotifier()

    /// Cache-first `load()` only runs brew once the inventory cache is stale, so a frequent tick is cheap.
    private static let checkInterval: Duration = .seconds(60 * 60)

    public init() {}

    public var body: some View {
        let summary = MenuBarSummary(outdated: repository.outdatedPackages)
        HStack(spacing: BrewSpacing.xxs) {
            Image(systemName: summary.badge == nil ? "mug" : "mug.fill")
            if let badge = summary.badge {
                Text(badge)
            }
        }
        .accessibilityLabel(Self.accessibilityLabel(for: summary))
        .task(id: checksAutomatically) {
            guard checksAutomatically else {
                return
            }
            while !Task.isCancelled {
                await repository.load()
                await notifier.checkCompleted(
                    outdatedNames: repository.outdatedPackages.map(\.name),
                    announce: notifiesAboutUpgrades,
                )
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    private static func accessibilityLabel(for summary: MenuBarSummary) -> String {
        guard summary.totalCount > 0 else {
            return String(localized: "Brewly: everything is up to date", bundle: #bundle,
                          comment: "VoiceOver: menu bar icon with no upgrades")
        }
        return String(localized: "Brewly: \(summary.totalCount) upgrades available", bundle: #bundle,
                      comment: "VoiceOver: menu bar icon; %lld is the outdated count")
    }
}

public struct MenuBarExtraContent: View {
    @Environment(\.installedPackagesRepository) private var repository
    @Environment(\.mainWindowRequests) private var requests
    @Environment(\.openWindow) private var openWindow

    private let mainWindowID: String

    public init(mainWindowID: String) {
        self.mainWindowID = mainWindowID
    }

    public var body: some View {
        let summary = MenuBarSummary(outdated: repository.outdatedPackages)

        Text(headline(for: summary))
        if let failure = repository.refreshFailure {
            Text("Last check failed: \(failure.localizedDescription)", bundle: #bundle,
                 comment: "Menu bar: the last upgrade check failed; %@ is the error")
        }

        if !summary.rows.isEmpty {
            Divider()
            ForEach(summary.rows) { row in
                Button {
                    showUpgrades()
                } label: {
                    Text(verbatim: "\(row.name)  \(row.versions)")
                }
            }
            if summary.hiddenCount > 0 {
                Text("and \(summary.hiddenCount) more", bundle: #bundle,
                     comment: "Menu bar: count of outdated packages not listed")
            }
        }

        Divider()
        Button {
            Task { await repository.load(forceRefresh: true) }
        } label: {
            Text("Check for Upgrades", bundle: #bundle, comment: "Menu bar: runs brew update and re-checks")
        }
        Button {
            showUpgrades()
        } label: {
            Text("Open Upgrades…", bundle: #bundle, comment: "Menu bar: opens the main window on Upgrades")
        }
        Divider()
        SettingsLink {
            Text("Settings…", bundle: #bundle, comment: "Menu bar: opens Brewly settings")
        }
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit Brewly", bundle: #bundle, comment: "Menu bar: quits the app")
        }
    }

    private func headline(for summary: MenuBarSummary) -> String {
        switch summary.totalCount {
        case 0:
            String(localized: "Everything is up to date", bundle: #bundle, comment: "Menu bar: no upgrades")
        case 1:
            String(localized: "1 upgrade available", bundle: #bundle, comment: "Menu bar: one upgrade")
        default:
            String(localized: "\(summary.totalCount) upgrades available", bundle: #bundle,
                   comment: "Menu bar: several upgrades; %lld is the count")
        }
    }

    private func showUpgrades() {
        requests.pendingDestination = .upgrades
        openWindow(id: mainWindowID)
        NSApplication.shared.activate()
    }
}

public struct BrewlySettingsView: View {
    @AppStorage(MenuBarPreferenceKey.showsMenuBarExtra) private var showsMenuBarExtra = false
    @AppStorage(MenuBarPreferenceKey.checksAutomatically) private var checksAutomatically = true
    @AppStorage(MenuBarPreferenceKey.notifiesAboutUpgrades) private var notifiesAboutUpgrades = false
    @State private var notificationsDenied = false

    public init() {}

    public var body: some View {
        Form {
            Toggle(isOn: $showsMenuBarExtra) {
                Text("Show Brewly in the menu bar", bundle: #bundle, comment: "Settings: menu bar extra toggle")
                Text("Shows how many packages can be upgraded, even when the window is closed.", bundle: #bundle,
                     comment: "Settings: menu bar extra toggle detail")
            }
            Toggle(isOn: $checksAutomatically) {
                Text("Check for upgrades automatically", bundle: #bundle, comment: "Settings: periodic check toggle")
                Text("Uses `brew update-if-needed`, so Homebrew’s own auto-update settings apply. Nothing is upgraded automatically.",
                     bundle: #bundle, comment: "Settings: periodic check toggle detail")
            }
            .disabled(!showsMenuBarExtra)
            Toggle(isOn: $notifiesAboutUpgrades) {
                Text("Notify me about new upgrades", bundle: #bundle, comment: "Settings: upgrade notification toggle")
                if notificationsDenied {
                    Text("Notifications are turned off for Brewly in System Settings.", bundle: #bundle,
                         comment: "Settings: macOS denied notification permission")
                } else {
                    Text("Only packages that became outdated since the last check are announced.", bundle: #bundle,
                         comment: "Settings: upgrade notification toggle detail")
                }
            }
            .disabled(!showsMenuBarExtra || !checksAutomatically)
        }
        .formStyle(.grouped)
        .onChange(of: notifiesAboutUpgrades) { _, enabled in
            guard enabled else {
                return
            }
            Task {
                let granted = await UpgradeNotifier.requestAuthorization()
                notificationsDenied = !granted
                if !granted {
                    notifiesAboutUpgrades = false
                }
            }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
