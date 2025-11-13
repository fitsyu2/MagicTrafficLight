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
            .onOpenURL { url in
                handleIncomingURL(url)
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
    
    private func handleIncomingURL(_ url: URL) {
        // Handle deep link URLs
        // Expected format: magictrafficlight://navigate?destination=DESTINATION_QUERY
        //                  magictrafficlight://search?q=SEARCH_QUERY
        //                  magictrafficlight://search (opens search without query)
        //                  magictrafficlight://route?lat=LATITUDE&lng=LONGITUDE
        
        guard url.scheme == "magictrafficlight" else { return }
        
        switch url.host {
        case "navigate":
            handleNavigateURL(url)
        case "search":
            handleSearchURL(url)
        case "route":
            handleRouteURL(url)
        default:
            // Default to opening search
            handleSiriOpenSearch()
        }
    }
    
    private func handleNavigateURL(_ url: URL) {
        // Parse destination from URL parameters
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = urlComponents.queryItems,
              let destination = queryItems.first(where: { $0.name == "destination" })?.value,
              !destination.isEmpty else {
            // If no destination provided, just open search
            handleSiriOpenSearch()
            return
        }
        
        // Post notification with destination to search for and navigate
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToDestination"),
            object: nil,
            userInfo: ["destination": destination]
        )
    }
    
    private func handleSearchURL(_ url: URL) {
        // Parse search query from URL parameters (optional)
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = urlComponents.queryItems,
              let searchQuery = queryItems.first(where: { $0.name == "q" })?.value,
              !searchQuery.isEmpty else {
            // If no search query provided, just open search
            handleSiriOpenSearch()
            return
        }
        
        // Post notification with search query
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenSearchWithQuery"),
            object: nil,
            userInfo: ["query": searchQuery]
        )
    }
    
    private func handleRouteURL(_ url: URL) {
        print("🔍 handleRouteURL called with URL: \(url)")
        
        // Parse lat and lng from URL parameters
        // Expected format: magictrafficlight://route?lat=LATITUDE&lng=LONGITUDE
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = urlComponents.queryItems else {
            print("❌ Failed to parse URL components or queryItems")
            handleSiriOpenSearch()
            return
        }
        
        print("📋 Query items: \(queryItems)")
        
        guard let latString = queryItems.first(where: { $0.name == "lat" })?.value,
              let lngString = queryItems.first(where: { $0.name == "lng" })?.value,
              let latitude = Double(latString),
              let longitude = Double(lngString) else {
            print("❌ Failed to extract or convert lat/lng parameters")
            print("   lat parameter: \(queryItems.first(where: { $0.name == "lat" })?.value ?? "nil")")
            print("   lng parameter: \(queryItems.first(where: { $0.name == "lng" })?.value ?? "nil")")
            // If lat/lng not provided or invalid, fall back to search
            handleSiriOpenSearch()
            return
        }
        
        print("✅ Parsed coordinates: lat=\(latitude), lng=\(longitude)")
        
        // Validate coordinate ranges
        guard latitude >= -90 && latitude <= 90 &&
              longitude >= -180 && longitude <= 180 else {
            print("❌ Invalid coordinate ranges: lat=\(latitude), lng=\(longitude)")
            // Invalid coordinates, fall back to search
            handleSiriOpenSearch()
            return
        }
        
        print("🚀 Posting OpenRoutePreview notification with coordinates")
        
        // Post notification to open route preview with coordinates
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenRoutePreview"),
            object: nil,
            userInfo: [
                "latitude": latitude,
                "longitude": longitude
            ]
        )
    }
}
