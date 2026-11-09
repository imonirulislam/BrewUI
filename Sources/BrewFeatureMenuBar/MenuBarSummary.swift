//
//  MenuBarSummary.swift
//  BrewFeatureMenuBar
//

import BrewCore
import Foundation

/// What the menu bar extra shows for a set of outdated packages.
struct MenuBarSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let id: HomebrewPackageID
        let name: String
        let versions: String
    }

    static let maximumRows = 10

    /// `nil` when nothing is outdated, so the menu bar shows only the icon.
    let badge: String?
    let totalCount: Int
    let rows: [Row]
    let hiddenCount: Int

    init(outdated: [InstalledBrewPackage]) {
        let sorted = outdated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        totalCount = sorted.count
        badge = sorted.isEmpty ? nil : sorted.count.formatted()
        rows = sorted.prefix(Self.maximumRows).map { package in
            Row(id: package.id, name: package.name, versions: Self.versions(for: package))
        }
        hiddenCount = max(0, sorted.count - Self.maximumRows)
    }

    private static func versions(for package: InstalledBrewPackage) -> String {
        let latest = package.latestVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let installed = package.linkedKeg ?? package.installedVersions.last, !installed.isEmpty else {
            return "→ \(latest)"
        }
        return "\(installed) → \(latest)"
    }
}
