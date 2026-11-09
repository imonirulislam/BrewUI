//
//  NavigationUITests.swift
//  BrewUITests
//

import BrewAccessibilityID
import XCTest

/// Every sidebar destination renders. A root that never appears is a crash or a composition mistake.
final class NavigationUITests: BrewUITestCase {
    @MainActor
    func testVisitsEverySidebarDestination() {
        let installed = launch(.installedBasic)

        installed.sidebar.goToUpgrades()
        installed.sidebar.goToDiscover()
        installed.sidebar.goToServices()
        installed.sidebar.goToDoctor()
        installed.sidebar.goToConfiguration()
        installed.sidebar.goToInstalled()
    }

    /// ⌘1–⌘8 follow sidebar order; the Assistant (⌘4) and Taps (⌘6) have no screen identifier of their own.
    @MainActor
    func testCommandNumbersFollowSidebarOrder() {
        let app = launch(.installedBasic).app
        let destinations: [(key: Int, screen: AXID)] = [
            (1, .installedScreen), (2, .upgradesScreen), (3, .discoverScreen),
            (5, .servicesScreen), (7, .doctorScreen), (8, .configScreen),
        ]
        for destination in destinations {
            app.typeKey(XCUIKeyboardKey(rawValue: "\(destination.key)"), modifierFlags: .command)
            BrewUIElement(app, destination.screen).assertExists()
        }
    }

    @MainActor
    func testReturningToADestinationKeepsItLoaded() {
        let installed = launch(.installedBasic)

        installed.sidebar.goToDiscover()
        installed.sidebar
            .goToInstalled()
            .assertHasPackage("wget")
    }
}
