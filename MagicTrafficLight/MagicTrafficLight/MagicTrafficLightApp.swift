//
//  MagicTrafficLightApp.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI

@main
struct MagicTrafficLightApp: App {
    @State private var showLaunchScreen = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchScreenView {
                        showLaunchScreen = false
                    }
                } else {
                    ContentView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SiriStartNavigation"))) { _ in
                handleSiriStartNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SiriStopNavigation"))) { _ in
                handleSiriStopNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SiriOpenSearch"))) { _ in
                handleSiriOpenSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SiriShowTrafficLightStatus"))) { _ in
                handleSiriTrafficLightStatus()
            }
        }
    }
    
    private func handleSiriStartNavigation() {
        // Start navigation only if there's a route preview ready, otherwise open search
        NotificationCenter.default.post(
            name: NSNotification.Name("StartNavigationWithFallback"),
            object: nil
        )
    }
    
    private func handleSiriStopNavigation() {
        // Stop ongoing navigation if active
        NotificationCenter.default.post(
            name: NSNotification.Name("StopActiveNavigation"),
            object: nil
        )
    }
    
    private func handleSiriOpenSearch() {
        // Open search dialog - this will be handled by the UI layer
        // The navigation to search view will be handled by ContentView/MainNavigationView
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenSearchDialog"),
            object: nil
        )
    }
    
    private func handleSiriTrafficLightStatus() {
        // Show traffic light status - handled by UI layer
        // This will focus on the traffic light view and show current status
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowTrafficLightStatus"),
            object: nil
        )
    }
}
