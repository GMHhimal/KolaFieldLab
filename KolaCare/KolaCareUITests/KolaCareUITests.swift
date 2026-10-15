//
//  KolaCareUITests.swift
//  KolaCareUITests
//
//  End-to-end flows driven through the UI. Launch arguments give each test a
//  clean, in-memory store and a known onboarding state. Run on an English
//  simulator (labels are matched in English where no identifier is set).
//

import XCTest

final class KolaCareUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_LK"]
    }

    private func launch(skipOnboarding: Bool = true, demoData: Bool = false) {
        app.launchArguments.append(skipOnboarding ? "-skipOnboarding" : "-resetOnboarding")
        if demoData { app.launchArguments.append("-seedDemoData") }
        app.launch()
    }

    private func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    // MARK: Onboarding

    func testOnboardingLeadsToDashboard() {
        launch(skipOnboarding: false)
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap(); next.tap(); next.tap()            // three feature pages
        XCTAssertTrue(app.buttons["onboarding.crop.rice"].waitForExistence(timeout: 3))
        app.buttons["onboarding.crop.rice"].tap()
        next.tap()                                     // Get started
        dismissSystemAlertIfNeeded()
        XCTAssertTrue(tab("Home").waitForExistence(timeout: 5))
    }

    func testSkipJumpsToCropPicker() {
        launch(skipOnboarding: false)
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["What do you grow?"].waitForExistence(timeout: 3))
    }

    // MARK: Navigation

    func testAllTabsAreReachable() {
        launch()
        for (name, title) in [("Garden", "My garden"), ("Scan", "Scan a leaf"), ("Map", "Field map"), ("Library", "Disease library")] {
            tab(name).tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(name) tab should show \(title)")
        }
    }

    // MARK: Garden

    func testAddPlantFlow() {
        launch()
        tab("Garden").tap()
        app.buttons["garden.add"].tap()

        let name = app.textFields["addPlant.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["addPlant.save"].isEnabled, "Save is disabled until a name is entered")
        name.typeText("Chilli row 1")
        app.buttons["addPlant.save"].tap()

        XCTAssertTrue(app.buttons["garden.plant.Chilli row 1"].waitForExistence(timeout: 5))
    }

    func testDemoGardenAndPlantDetail() {
        launch(demoData: true)
        tab("Garden").tap()
        let card = app.buttons["garden.plant.Tomato bed A"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.staticTexts["Health trend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scan history"].exists)
    }

    // MARK: Scan

    func testSampleLeafScanAndSave() {
        launch(demoData: true)
        tab("Scan").tap()
        app.buttons["scan.sample"].tap()
        app.buttons["Spotted leaf"].tap()

        let diseaseName = app.staticTexts["result.diseaseName"]
        XCTAssertTrue(diseaseName.waitForExistence(timeout: 10), "diagnosis screen appears")

        let save = app.buttons["result.save"]
        app.swipeUp()
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.otherElements["result.saved"].waitForExistence(timeout: 3)
                      || app.staticTexts["Saved to your garden"].waitForExistence(timeout: 3))
    }

    // MARK: Library

    func testLibrarySearchOpensGuide() {
        launch()
        tab("Library").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("blast")
        let row = app.buttons["library.disease.rice.blast"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["Symptoms"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Treatment"].exists)
    }

    // MARK: Accessibility & performance

    func testDashboardSupportsLargestDynamicType() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(demoData: true)
        XCTAssertTrue(tab("Home").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Garden health"].waitForExistence(timeout: 5))
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: Helpers

    private func dismissSystemAlertIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }
}
