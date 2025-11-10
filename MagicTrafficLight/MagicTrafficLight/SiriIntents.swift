import Foundation
import AppIntents
import SwiftUI

// MARK: - Start Navigation Intent
@available(iOS 16.0, *)
struct StartNavigationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Navigation"
    static var description = IntentDescription("Start navigation if route exists, otherwise open destination search")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Post notification to start navigation with route check and fallback to search
        NotificationCenter.default.post(
            name: NSNotification.Name("SiriStartNavigation"),
            object: nil
        )
        
        return .result(dialog: "Starting navigation or opening destination search")
    }
}

// MARK: - Stop Navigation Intent
@available(iOS 16.0, *)
struct StopNavigationIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Navigation"
    static var description = IntentDescription("Stop ongoing navigation if active")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Post notification to stop navigation
        NotificationCenter.default.post(
            name: NSNotification.Name("SiriStopNavigation"),
            object: nil
        )
        
        return .result(dialog: "Stopping navigation")
    }
}

// MARK: - Search Location Intent
@available(iOS 16.0, *)
struct SearchLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Location"
    static var description = IntentDescription("Open search dialog to find destinations")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Post notification to open search dialog
        NotificationCenter.default.post(
            name: NSNotification.Name("SiriOpenSearch"),
            object: nil
        )
        
        return .result(dialog: "Opening search to find destinations")
    }
}

// MARK: - Get Traffic Light Status Intent
@available(iOS 16.0, *)
struct GetTrafficLightStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Traffic Light Status"
    static var description = IntentDescription("Check the current Magic Traffic Light status")
    
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Post notification to show traffic light status
        NotificationCenter.default.post(
            name: NSNotification.Name("SiriShowTrafficLightStatus"),
            object: nil
        )
        
        return .result(dialog: "Showing Magic Traffic Light status")
    }
}

// MARK: - App Shortcuts Provider
@available(iOS 16.0, *)
struct MagicTrafficLightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNavigationIntent(),
            phrases: [
                "Start navigation in \(.applicationName)",
                "Begin navigation with \(.applicationName)",
                "Open \(.applicationName) for navigation"
            ],
            shortTitle: "Start Navigation",
            systemImageName: "location.fill"
        )
        
        AppShortcut(
            intent: StopNavigationIntent(),
            phrases: [
                "Stop navigation in \(.applicationName)",
                "End navigation with \(.applicationName)",
                "Cancel navigation in \(.applicationName)"
            ],
            shortTitle: "Stop Navigation",
            systemImageName: "stop.fill"
        )
        
        AppShortcut(
            intent: SearchLocationIntent(),
            phrases: [
                "Search location in \(.applicationName)",
                "Find location with \(.applicationName)",
                "Search places in \(.applicationName)"
            ],
            shortTitle: "Search Location",
            systemImageName: "magnifyingglass"
        )
        
        AppShortcut(
            intent: GetTrafficLightStatusIntent(),
            phrases: [
                "Check traffic light status in \(.applicationName)",
                "Get traffic light status from \(.applicationName)",
                "Show traffic light status in \(.applicationName)"
            ],
            shortTitle: "Traffic Light Status",
            systemImageName: "light.beacon.max"
        )
    }
}