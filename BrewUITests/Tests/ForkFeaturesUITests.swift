//
//  ForkFeaturesUITests.swift
//  BrewUITests
//

import BrewAccessibilityID
import XCTest

/// Upgrade Selected, Taps and the Go to palette, driven through the deterministic fixtures.
final class ForkFeaturesUITests: BrewUITestCase {
    // MARK: - Upgrade Selected

    @MainActor
    func testTickingARowSwitchesTheBatchToTheSelection() {
        let upgrades = launch(.installedBasic).sidebar.goToUpgrades()
        let app = upgrades.app
        let batch = BrewUIButton(app, .upgradesBatchButton)
        batch.waitToExist()
        XCTAssertTrue(batch.element.label.contains("all"), "Expected Upgrade All, got \(batch.element.label)")

        BrewUIButton(app, .upgradesRowCheckbox(token: "ripgrep")).tap()

        XCTAssertTrue(batch.element.label.contains("selected"), "Expected Upgrade Selected, got \(batch.element.label)")
        XCTAssertTrue(app.staticTexts.containing(Self.text("brew upgrade ripgrep")).firstMatch.waitForExistence(timeout: 5))

        BrewUIButton(app, .upgradesDeselectAllButton).tap()

        BrewUIButton(app, .upgradesDeselectAllButton).assertDoesNotExist()
        XCTAssertTrue(batch.element.label.contains("all"), "Expected Upgrade All after Deselect All")
    }

    // MARK: - Taps

    @MainActor
    func testOfficialTapsCannotBeRemovedButThirdPartyOnesCan() {
        let app = launch(.installedBasic).app
        openTaps(app)

        BrewUIElement(app, .tapsRow(name: "homebrew/core")).element.click()
        BrewUIButton(app, .tapsRemoveButton).assertIsDisabled()

        BrewUIElement(app, .tapsRow(name: "example/tools")).element.click()
        BrewUIButton(app, .tapsRemoveButton).assertIsEnabled()
    }

    @MainActor
    func testArrowKeysMoveThroughTheTapList() {
        let app = launch(.installedBasic).app
        openTaps(app)

        BrewUIElement(app, .tapsRow(name: "example/tools")).element.click()
        app.typeKey(.downArrow, modifierFlags: [])

        BrewUIButton(app, .tapsRemoveButton).assertIsDisabled()
    }

    @MainActor
    func testAddingATapShowsTheExactCommandBeforeRunningIt() {
        let app = launch(.installedBasic).app
        openTaps(app)
        let addButton = BrewUIButton(app, .tapsAddButton)
        addButton.assertIsDisabled()

        let field = BrewUIElement(app, .tapsAddField).element
        field.click()
        field.typeText("someone/tools")
        addButton.tap()

        XCTAssertTrue(app.staticTexts.containing(Self.text("brew tap someone/tools")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        BrewUIElement(app, .tapsRow(name: "someone/tools")).assertDoesNotExist()
    }

    // MARK: - Go to

    @MainActor
    func testGoToOpensAPage() {
        let app = launch(.installedBasic).app

        app.typeKey("k", modifierFlags: .command)
        BrewUIElement(app, .goToPalette).waitToExist()
        app.typeText("taps")
        BrewUIElement(app, .goToRow(id: "page-taps")).waitToExist()
        app.typeKey(.return, modifierFlags: [])

        BrewUIElement(app, .tapsScreen).waitToExist()
        BrewUIElement(app, .goToPalette).assertDoesNotExist()
    }

    @MainActor
    func testGoToSelectsAnInstalledPackage() {
        let app = launch(.installedBasic).sidebar.goToDiscover().app

        app.typeKey("k", modifierFlags: .command)
        app.typeText("ripgrep")
        BrewUIElement(app, .goToRow(id: "installed-ripgrep")).waitToExist()
        app.typeKey(.return, modifierFlags: [])

        BrewUIElement(app, .installedScreen).waitToExist()
        let detail = BrewUIElement(app, .packageDetail).element
        XCTAssertTrue(detail.staticTexts.containing(Self.text("ripgrep")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    @MainActor
    private func openTaps(_ app: XCUIApplication) {
        BrewUIButton(app, .sidebarItem(.taps)).tap()
        BrewUIElement(app, .tapsRow(name: "example/tools")).waitToExist()
    }

    /// macOS exposes list text through the accessibility value as often as the label.
    private static func text(_ fragment: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fragment, fragment)
    }
}
