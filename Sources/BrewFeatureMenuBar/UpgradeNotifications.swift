//
//  UpgradeNotifications.swift
//  BrewFeatureMenuBar
//

import Foundation
import UserNotifications

/// Decides which outdated packages are news. Only names never seen outdated before are announced, and a
/// package that gets upgraded drops out, so its next release is announced again.
enum UpgradeNotificationPlanner {
    struct Plan: Equatable {
        let newNames: [String]
        let seen: Set<String>
    }

    static func plan(outdatedNames: [String], previouslySeen: Set<String>?) -> Plan {
        let current = Set(outdatedNames)
        guard let previouslySeen else {
            return Plan(newNames: [], seen: current)
        }
        let new = current.subtracting(previouslySeen).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Plan(newNames: new, seen: current)
    }

    static func body(for names: [String]) -> String {
        switch names.count {
        case 1:
            String(localized: "\(names[0]) can be upgraded", bundle: #bundle,
                   comment: "Upgrade notification body; %@ is a package name")
        case 2:
            String(localized: "\(names[0]) and \(names[1]) can be upgraded", bundle: #bundle,
                   comment: "Upgrade notification body; %1$@ and %2$@ are package names")
        default:
            String(localized: "\(names[0]), \(names[1]) and \(names.count - 2) more can be upgraded", bundle: #bundle,
                   comment: "Upgrade notification body; %1$@ and %2$@ are package names, %3$lld how many others")
        }
    }
}

/// Keeps what was last seen outdated across launches, so a relaunch does not re-announce everything.
@MainActor
final class UpgradeNotifier {
    private static let seenKey = "menuBarNotifiedOutdatedNames"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records every check, so turning notifications on later announces only what is new from then on.
    func checkCompleted(outdatedNames: [String], announce: Bool) async {
        let previous = defaults.stringArray(forKey: Self.seenKey).map(Set.init)
        let plan = UpgradeNotificationPlanner.plan(outdatedNames: outdatedNames, previouslySeen: previous)
        defaults.set(plan.seen.sorted(), forKey: Self.seenKey)
        guard announce, !plan.newNames.isEmpty else {
            return
        }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Upgrades available", bundle: #bundle, comment: "Upgrade notification title")
        content.body = UpgradeNotificationPlanner.body(for: plan.newNames)
        try? await center.add(UNNotificationRequest(identifier: "brewly.upgrades", content: content, trigger: nil))
    }

    /// Asks once, when the user turns notifications on; macOS remembers the answer.
    static func requestAuthorization() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }
}
