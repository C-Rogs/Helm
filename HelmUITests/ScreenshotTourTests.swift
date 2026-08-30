import UIKit
import XCTest

/// Drives the booted Simulator through main tabs + Settings destinations
/// and writes PNGs under `Screenshots/tour/` at the repo root.
@MainActor
final class ScreenshotTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        outputDirectory = try Self.makeOutputDirectory()
        app = XCUIApplication()
        app.launchArguments += ["-helm-uitesting"]
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "Signal failed to reach foreground"
        )
        // Let first-frame bootstrap settle (readiness / prescription refresh).
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    func testScreenshotTour() throws {
        capture("01-dashboard")

        openTab("Train")
        capture("02-train")

        openTab("Nutrition")
        capture("03-nutrition")

        openTab("Chat")
        capture("04-chat")

        openTab("Settings")
        capture("05-settings")

        for (index, title) in Self.settingsDestinations.enumerated() {
            openSettingsDestination(title)
            let slug = Self.slug(title)
            capture(String(format: "06-%02d-settings-%@", index + 1, slug))
            dismissSettingsDestination(title)
        }

        openTab("Dashboard")
        tryOpenDashboardDetail(matching: "Sleep", name: "07-sleep-analysis")
        tryOpenDashboardDetail(matching: "Muscle", name: "08-muscle-volume")
        tryOpenDashboardDetail(matching: "TODAY", name: "09-progression-detail")

        openTab("Train")
        tryOpenNamedLink("Plan", name: "10-train-plan")

        let manifest = outputDirectory.appendingPathComponent("MANIFEST.txt")
        let listing = try FileManager.default
            .contentsOfDirectory(atPath: outputDirectory.path)
            .sorted()
            .joined(separator: "\n")
        try """
        Helm screenshot tour
        Device: \(UIDevice.current.model)
        Output: \(outputDirectory.path)

        \(listing)

        """.write(to: manifest, atomically: true, encoding: .utf8)

        print("HELM_SCREENSHOTS=\(outputDirectory.path)")
    }

    // MARK: - Navigation

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        guard tab.waitForExistence(timeout: 8) else {
            XCTFail("Tab \(name) missing")
            return
        }
        tab.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    private func openSettingsDestination(_ title: String) {
        var link = settingsLink(title)
        if !link.waitForExistence(timeout: 2) {
            scrollSettingsToward(title)
            link = settingsLink(title)
            guard link.waitForExistence(timeout: 4) else {
                XCTFail("Settings link \(title) missing")
                return
            }
        }
        link.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
    }

    private func dismissSettingsDestination(_ title: String) {
        if Self.sheetDestinations.contains(title) {
            let close = app.buttons["Close"]
            if close.waitForExistence(timeout: 2) {
                close.tap()
                _ = app.navigationBars["Settings"].waitForExistence(timeout: 4)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                return
            }
        }
        navigateBackToSettings()
    }

    private func navigateBackToSettings() {
        if app.navigationBars["Settings"].waitForExistence(timeout: 1) {
            return
        }
        let back = app.navigationBars.buttons.firstMatch
        if back.exists {
            back.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 4)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func tryOpenDashboardDetail(matching needle: String, name: String) {
        openTab("Dashboard")
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", needle))
            .firstMatch
        guard match.waitForExistence(timeout: 3), match.isHittable else {
            return
        }
        match.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        capture(name)
        if !app.navigationBars["Dashboard"].exists {
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            _ = app.navigationBars["Dashboard"].waitForExistence(timeout: 4)
        }
    }

    private func tryOpenNamedLink(_ title: String, name: String) {
        let link = contentLink(title)
        guard link.waitForExistence(timeout: 3), link.isHittable else { return }
        link.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        capture(name)
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    /// Settings / content links; never tab bar (avoids Nutrition tab vs Settings row clash).
    private func settingsLink(_ title: String) -> XCUIElement {
        contentLink(title)
    }

    private func contentLink(_ title: String) -> XCUIElement {
        let collections = app.collectionViews
        if collections.buttons[title].exists { return collections.buttons[title] }
        if collections.staticTexts[title].exists { return collections.staticTexts[title] }
        if collections.cells.containing(.staticText, identifier: title).firstMatch.exists {
            return collections.cells.containing(.staticText, identifier: title).firstMatch
        }

        let tables = app.tables
        if tables.buttons[title].exists { return tables.buttons[title] }
        if tables.staticTexts[title].exists { return tables.staticTexts[title] }
        if tables.cells[title].exists { return tables.cells[title] }

        // ScrollViews hosting NavigationLink labels (non-List screens).
        let scrolls = app.scrollViews
        if scrolls.buttons[title].exists { return scrolls.buttons[title] }
        if scrolls.staticTexts[title].exists { return scrolls.staticTexts[title] }

        return collections.buttons[title]
    }

    private func scrollSettingsToward(_ title: String) {
        let list: XCUIElement = {
            if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
            return app.tables.firstMatch
        }()
        for _ in 0..<8 {
            if contentLink(title).exists { return }
            list.swipeUp()
        }
        for _ in 0..<8 {
            if contentLink(title).exists { return }
            list.swipeDown()
        }
    }

    // MARK: - Capture

    private func capture(_ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try shot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Failed writing \(url.lastPathComponent): \(error)")
        }
    }

    private static func makeOutputDirectory() throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot
            .appendingPathComponent("Screenshots", isDirectory: true)
            .appendingPathComponent("tour", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        for file in existing where file.pathExtension == "png" || file.lastPathComponent == "MANIFEST.txt" {
            try? FileManager.default.removeItem(at: file)
        }
        return dir
    }

    private static func slug(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static let sheetDestinations: Set<String> = ["Training plan"]

    private static let settingsDestinations = [
        "Send feedback",
        "Training plan",
        "Body Profile",
        "Plan details",
        "Nutrition",
        "Sources & Methodology",
        "Coach settings",
        "Coach Memory",
        "Notifications",
        "Apple Health",
        "Spotify",
        "Calendar Hints",
        "Watch Sync",
        "Data & Backup",
        "Export health data",
        "Diagnostics",
        "Sleep diagnostics",
    ]
}
