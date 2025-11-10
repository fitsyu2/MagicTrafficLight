//
//  NavigationControlView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI
import MapKit

struct NavigationControlView: View {
    @ObservedObject var navigationManager: NavigationManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var aiMessage: String = ""
    
    // Check if we're in landscape mode
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    // AI-generated messages for different states
    private let aiMessages: [TrafficLightState: [String]] = [
        .red: [
            "🛑 Take a moment to breathe and plan your next move",
            "⏱️ Perfect time to check your route details",
            "🚫 Hold tight, good things come to those who wait",
            "📱 Use this pause to ensure you're ready",
            "🔄 Patience leads to smoother journeys"
        ],
        .yellow: [
            "⚠️ Prepare for the next phase of your journey",
            "🔔 Get ready, change is coming",
            "⏳ Transition time - stay alert",
            "🎯 Focus up, movement ahead",
            "⚡ Energy building for the next move"
        ],
        .green: [
            "✅ You're good to go! Navigate with confidence",
            "🚀 All systems go - enjoy your journey",
            "🎉 Clear path ahead, drive safely",
            "💚 Green means go - you've got this",
            "🛣️ Smooth sailing from here"
        ],
        .off: [
            "🌟 Magic Traffic Light ready to guide you",
            "🧭 Your AI navigation companion awaits",
            "✨ Let's make your journey magical",
            "🎨 Ready to paint your path with smart guidance",
            "🔮 Intelligent navigation at your service"
        ]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            // AI Message (always at top)
            if !aiMessage.isEmpty {
                Text(aiMessage)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
            
            if let destination = navigationManager.destination {
                destinationCard
            }
            
            if navigationManager.currentRoute != nil && !navigationManager.isNavigating {
                startNavigationButton
            }
            
            if navigationManager.isNavigating {
                if isLandscape {
                    compactTurnByTurnView
                } else {
                    turnByTurnView
                }
            }
        }
        .onAppear {
            updateAIMessage()
        }
        .onChange(of: navigationManager.isNavigating) { _, _ in
            updateAIMessage()
        }
        .onChange(of: navigationManager.currentRoute) { _, _ in
            updateAIMessage()
        }
        .onChange(of: navigationManager.isCalculatingRoute) { _, _ in
            updateAIMessage()
        }
    }
    
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destination")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(navigationManager.destination?.name ?? "Unknown Location")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            
            // Route information or loading state
            if navigationManager.isCalculatingRoute {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Calculating route...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if let error = navigationManager.routeCalculationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if let route = navigationManager.currentRoute {
                HStack {
                    Label(formatDistance(route.distance), systemImage: "location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Label(formatTime(route.expectedTravelTime), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var startNavigationButton: some View {
        Button(action: {
            navigationManager.startNavigation()
        }) {
            HStack {
                if navigationManager.isCalculatingRoute {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "location.north.fill")
                }
                Text(navigationManager.isCalculatingRoute ? "Calculating..." : "Start Navigation")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(navigationManager.isCalculatingRoute ? .gray : .blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(navigationManager.isCalculatingRoute || navigationManager.currentRoute == nil)
    }
    
    private var compactTurnByTurnView: some View {
        VStack(spacing: 8) { // Reduced from 12
            // Main instruction row
            HStack(spacing: 16) {
                // Maneuver Icon - larger for landscape
                if let currentStep = navigationManager.currentStep {
                    Image(systemName: getManeuverIcon(for: currentStep))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(.blue)
                        .cornerRadius(12)
                }
                
                // Navigation Info - better spacing for landscape
                VStack(alignment: .leading, spacing: 4) { // Reduced from 6
                    if let currentStep = navigationManager.currentStep {
                        Text(currentStep.instructions.isEmpty ? "Continue straight" : currentStep.instructions)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2) // Allow 2 lines for better readability
                            .multilineTextAlignment(.leading)
                        
                        // Distance to next maneuver - more prominent
                        if navigationManager.currentStepRemainingDistance > 0 {
                            Text("in \(formatDistance(navigationManager.currentStepRemainingDistance))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12) // Reduced from 16
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var turnByTurnView: some View {
        VStack(spacing: 12) { // Reduced from 16
            // Current Step
            if let currentStep = navigationManager.currentStep {
                HStack {
                    // Maneuver Icon - consistent with landscape
                    Image(systemName: getManeuverIcon(for: currentStep))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(.blue)
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) { // Reduced from 6
                        Text(currentStep.instructions.isEmpty ? "Continue straight" : currentStep.instructions)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3) // Allow more lines for portrait
                        
                        if navigationManager.currentStepRemainingDistance > 0 {
                            Text("in \(formatDistance(navigationManager.currentStepRemainingDistance))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12) // Reduced from 16
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Helper Functions
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: distance)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: time) ?? "0m"
    }
    
    private func getManeuverIcon(for step: MKRoute.Step) -> String {
        // Simple mapping of common navigation instructions to SF Symbols
        let instruction = step.instructions.lowercased()
        
        if instruction.contains("left") {
            return "arrow.turn.up.left"
        } else if instruction.contains("right") {
            return "arrow.turn.up.right"
        } else if instruction.contains("continue") || instruction.contains("straight") {
            return "arrow.up"
        } else if instruction.contains("merge") {
            return "arrow.merge"
        } else if instruction.contains("exit") {
            return "arrow.uturn.left"
        } else {
            return "arrow.up"
        }
    }
    
    // MARK: - AI Message Functions
    
    private func updateAIMessage() {
        let state = determineTrafficLightState()
        withAnimation(.easeInOut(duration: 0.5)) {
            aiMessage = getRandomMessage(for: state)
        }
    }
    
    private func determineTrafficLightState() -> TrafficLightState {
        if navigationManager.isCalculatingRoute {
            return .yellow
        } else if navigationManager.isNavigating {
            return .green
        } else if navigationManager.currentRoute != nil {
            return .yellow
        } else {
            return .off
        }
    }
    
    private func getRandomMessage(for state: TrafficLightState) -> String {
        guard let messages = aiMessages[state] else { return "" }
        return messages.randomElement() ?? ""
    }
}
