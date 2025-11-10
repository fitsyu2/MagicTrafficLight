//
//  MainNavigationView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI
import MapKit
import Foundation

#if os(iOS)
import UIKit
#endif

struct MainNavigationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var navigationManager = NavigationManager()
    @State private var showingSearch = false
    @State private var showingLocationPermissionAlert = false
    @State private var trafficLightView = TrafficLightView()
    @State private var isMapInMiniMode = false
    @State private var isTeleVisionFullScreen = false
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Check if we're in landscape mode
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    var body: some View {
        ZStack {
            // Map View (Full Background)
            MapView(
                locationManager: locationManager,
                navigationManager: navigationManager
            )
            .ignoresSafeArea()
            
            // Main navigation content overlay
            navigationContentOverlay
        }
        .sheet(isPresented: $showingSearch) {
            NavigationView {
                SearchView(navigationManager: navigationManager) {
                    showingSearch = false
                }
                    .navigationTitle("Search Destination")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingSearch = false
                            }
                        }
                    }
            }
        }
        .alert("Location Permission Required", isPresented: $showingLocationPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable location access in Settings to use navigation features.")
        }
        .onAppear {
            locationManager.requestLocationPermission()
            
            // Request Live Activity permission
            Task {
                await navigationManager.liveActivityManager.requestLiveActivityPermission()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            if status == .denied || status == .restricted {
                showingLocationPermissionAlert = true
            }
        }
        .onChange(of: navigationManager.isNavigating) { _, isNavigating in
            updateTrafficLightState()
            updateIdleTimerDisabled(isNavigating: isNavigating)
        }
        .onChange(of: navigationManager.currentRoute) { _, route in
            updateTrafficLightState()
        }
        .onChange(of: navigationManager.isCalculatingRoute) { _, isCalculating in
            updateTrafficLightState()
        }
        .onAppear {
            // Ensure idle timer is initially enabled (screen can lock)
            updateIdleTimerDisabled(isNavigating: navigationManager.isNavigating)
        }
        .onDisappear {
            // Re-enable idle timer when view disappears to allow normal screen locking
            updateIdleTimerDisabled(isNavigating: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSearchDialog"))) { _ in
            showingSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTrafficLightStatus"))) { _ in
            // Focus on traffic light and show status
            // This could trigger an animation or highlight the traffic light
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                trafficLightView.cycleStates()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if navigationManager.isNavigating {
                TeleVisionView(locationManager: locationManager, navigationManager: navigationManager)
                    .padding(.trailing, isTeleVisionFullScreen ? 0 : 16)
                    .padding(.bottom, isTeleVisionFullScreen ? 0 : 48)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TeleVisionFullScreenChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let isFullScreen = userInfo["isFullScreen"] as? Bool {
                isTeleVisionFullScreen = isFullScreen
            }
        }
    }
    
    @ViewBuilder
    private var navigationContentOverlay: some View {
        // Overlay Content
        if isLandscape && navigationManager.isNavigating {
            // Landscape navigation layout - compact spacing for more TrafficLight space
            landscapeNavigationLayout
        } else if navigationManager.isNavigating {
            // Portrait navigation layout - TrafficLight on right side
            portraitNavigationLayout
        } else if navigationManager.currentRoute != nil && !navigationManager.isCalculatingRoute {
            // Route preview layout
            routePreviewLayout
        } else {
            // Non-navigating layout (logo and centered search bar with map background)
            defaultLayout
        }
    }
    
    // MARK: - Layout Views
    
    @ViewBuilder
    private var landscapeNavigationLayout: some View {
        HStack {
            VStack(spacing: 6) { // Reduced from 10
                trafficLightView
                    .frame(maxWidth: 320) // Slightly wider for landscape
                    .padding(.top, 8) // Reduced from 12
                    .padding(.leading, 16)
                
                NavigationControlView(navigationManager: navigationManager)
                    .frame(maxWidth: 320) // Matched width for consistency
                    .padding(.leading, 16)
                    .padding(.top, 4) // Reduced from 6
                
                Spacer()
                
                // Navigation buttons at bottom (landscape optimized)
                landscapeNavigationButtons
            }
            Spacer() // Push content to left, leave right side for map
        }
    }
    
    @ViewBuilder
    private var portraitNavigationLayout: some View {
        HStack(spacing: 12) {
            // Left side: Navigation content (60% of screen width)
            VStack(spacing: 6) {
                NavigationControlView(navigationManager: navigationManager)
                    .frame(maxWidth: .infinity) // Use available space up to 60%
                    .padding(.leading, 16)
                    .padding(.top, 8)
                
                Spacer() // Push navigation buttons to bottom
                
                // Navigation buttons at bottom (portrait)
                portraitNavigationButtons
            }
            .frame(maxWidth: .infinity) // Takes up to 60% when in HStack with TrafficLight
            .layoutPriority(1) // Give priority to navigation content
            
            // Right side: Vertical TrafficLight (40% of remaining space)
            VStack {
                trafficLightView
                    .frame(maxWidth: 120) // Fixed width for TrafficLight
                    .padding(.trailing, 16)
                    .padding(.top, 48) // Align with DestinationView top (below AI message)
                
                Spacer() // Bottom spacer to push TrafficLight to top
            }
            .frame(maxWidth: 120) // Constrain TrafficLight area
        }
    }
    
    @ViewBuilder
    private var routePreviewLayout: some View {
        VStack {
            Spacer()
            
            // Route Preview Card
            routePreviewCard
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var defaultLayout: some View {
        VStack(spacing: 40) {
            // Reduced top spacer to move content up
            Spacer()
            
            // Magic Traffic Light Logo
            Image("MagicTrafficLightLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 300)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            // Centered Search Bar (positioned higher for better accessibility)
            centeredSearchBar
            
            // Larger bottom spacer to balance the layout
            Spacer()
            Spacer()
        }
    }
    
    @ViewBuilder
    private var landscapeNavigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                navigationManager.previousStep()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 70)
            .buttonStyle(.bordered)
            .controlSize(.regular) // Larger for landscape
            .disabled(navigationManager.currentStepIndex <= 0)
            
            Button {
                navigationManager.nextStep()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 70)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(navigationManager.currentStepIndex >= (navigationManager.currentRoute?.steps.count ?? 1) - 1)
            
            Button("End Trip") {
                navigationManager.stopNavigation()
            }
            .frame(minWidth: 80)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .foregroundColor(.white)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8) // Reduced from 12
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        .frame(maxWidth: 320) // Match NavigationControlView width
        .padding(.leading, 16)
        .padding(.bottom, 12) // Reduced from 16
    }
    
    @ViewBuilder
    private var portraitNavigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                navigationManager.previousStep()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 80)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(navigationManager.currentStepIndex <= 0)
            
            Button {
                navigationManager.nextStep()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 80)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(navigationManager.currentStepIndex >= (navigationManager.currentRoute?.steps.count ?? 1) - 1)
            
            Button("End Trip") {
                navigationManager.stopNavigation()
            }
            .frame(minWidth: 90)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .foregroundColor(.white)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        .padding(.leading, 16)
        .padding(.bottom, 12)
    }
    
    private var topSearchBar: some View {
        HStack {
            Button(action: {
                showingSearch = true
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    Text("Search for a destination...")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !navigationManager.searchHistory.isEmpty {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var centeredSearchBar: some View {
        VStack(spacing: 16) {
            // Main search button with loading state support
            if navigationManager.isCalculatingRoute {
                // Show route calculation progress with cancel option
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("Calculating route...")
                            .foregroundColor(.secondary)
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Cancel button
                        Button(action: {
                            navigationManager.cancelRouteCalculation()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    if let destination = navigationManager.destination {
                        HStack {
                            Spacer()
                            
                            Text("to \(destination.name ?? "destination")")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        // Dark base background
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.black.opacity(0.9))
                                        
                                        // Animated shimmer overlay
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        .clear,
                                                        .cyan.opacity(0.3),
                                                        .blue.opacity(0.2),
                                                        .purple.opacity(0.3),
                                                        .clear
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .scaleEffect(x: 2, y: 1)
                                            .offset(x: -100)
                                            .animation(
                                                Animation.linear(duration: 2)
                                                    .repeatForever(autoreverses: false),
                                                value: destination.name
                                            )
                                    }
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.cyan.opacity(0.5), .blue.opacity(0.3), .purple.opacity(0.5)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: .cyan.opacity(0.3), radius: 8, x: 0, y: 0)
                                .shadow(color: .blue.opacity(0.2), radius: 4, x: 0, y: 2)
                            
                            Spacer()
                        }
                    }
                }
            } else {
                // Normal search button
                Button(action: {
                    showingSearch = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        Text("Where to?")
                            .foregroundColor(.secondary)
                            .font(.title3)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if !navigationManager.searchHistory.isEmpty {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: 300)
    }
    
    private var routePreviewCard: some View {
        VStack(spacing: 20) {
            // Route Information Card
            VStack(spacing: 16) {
                // Destination Header
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(navigationManager.destination?.name ?? "Unknown Destination")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        
                        if let address = navigationManager.destination?.placemark.title {
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Route Stats
                if let route = navigationManager.currentRoute {
                    HStack(spacing: 20) {
                        // Distance
                        VStack(spacing: 4) {
                            Image(systemName: "road.lanes")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            Text(formatDistance(route.distance))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Distance")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Travel Time
                        VStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            Text(formatTime(route.expectedTravelTime))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Travel Time")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Steps Count
                        VStack(spacing: 4) {
                            Image(systemName: "list.number")
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            Text("\(route.steps.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Steps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Action Buttons
                HStack(spacing: 12) {
                    // Cancel Route Button
                    Button(action: {
                        navigationManager.stopNavigation() // This will clear the route
                    }) {
                        HStack {
                            Image(systemName: "xmark")
                            Text("Cancel")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                    }
                    .foregroundColor(.red)
                    
                    // Start Navigation Button
                    Button(action: {
                        navigationManager.startNavigation()
                    }) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Start")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .cornerRadius(12)
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .frame(maxWidth: 350)
            
            // Optional: Search Again Button
            Button(action: {
                showingSearch = true
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search Another Destination")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // Update traffic light based on navigation state
    private func updateTrafficLightState() {
        trafficLightView.updateForNavigationState(
            isNavigating: navigationManager.isNavigating,
            hasRoute: navigationManager.currentRoute != nil,
            isCalculating: navigationManager.isCalculatingRoute
        )
    }
    
    // Control idle timer to prevent screen lock during navigation
    private func updateIdleTimerDisabled(isNavigating: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isNavigating
        }
    }
    
    // Helper functions for formatting
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: distance)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    MainNavigationView()
}
