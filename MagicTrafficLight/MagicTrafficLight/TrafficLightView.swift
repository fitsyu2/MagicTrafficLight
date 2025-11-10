//
//  TrafficLightView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI
import AVFoundation
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

struct TrafficLightView: View {
    @State private var currentState: TrafficLightState = .off
    @State private var aiMessage: String = ""
    @State private var isAnimating = false
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @StateObject private var activityManager = TrafficLightActivityManager()
    
    // Check if we're in portrait mode
    private var isPortrait: Bool {
        verticalSizeClass != .compact
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
        // Traffic Light - Vertical in Portrait, Horizontal in Landscape
        Group {
            if isPortrait {
                // Vertical Traffic Light (Portrait Mode)
                VStack(spacing: 8) {
                    trafficLightCircle(for: .red)
                    trafficLightCircle(for: .yellow)
                    trafficLightCircle(for: .green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .cornerRadius(18)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            } else {
                // Horizontal Traffic Light (Landscape Mode)
                HStack(spacing: 12) {
                    trafficLightCircle(for: .red)
                    trafficLightCircle(for: .yellow)
                    trafficLightCircle(for: .green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .cornerRadius(18)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            }
        }
        .onTapGesture {
            manualStateChange()
        }
        .onAppear {
            updateTrafficLight()
            // Start LiveActivity with current state if not already active
            Task {
                if activityManager.currentActivity == nil && currentState != .off {
                    updateLiveActivity(for: currentState)
                }
            }
        }
        .onDisappear {
            // End LiveActivity when TrafficLight view disappears
            Task {
                activityManager.endTrafficLightActivity()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentState)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
    }
    
    // Helper function to create individual traffic light circles
    @ViewBuilder
    private func trafficLightCircle(for state: TrafficLightState) -> some View {
        Circle()
            .fill(currentState == state ? 
                  stateColor(for: state).opacity(0.9) : 
                  Color.gray.opacity(0.3))
            .frame(width: 36, height: 36)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: currentState == state ? stateColor(for: state).opacity(0.6) : .clear, radius: 6)
            .scaleEffect(currentState == state && isAnimating ? 1.1 : 1.0)
    }
    
    // Helper function to get color for each state
    private func stateColor(for state: TrafficLightState) -> Color {
        switch state {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .off: return .gray
        }
    }
    
    // Public methods to control the traffic light
    func setState(_ state: TrafficLightState) {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentState = state
            updateMessage()
            updateAnimation()
            playSound(for: state)
            
            // Update LiveActivity
            updateLiveActivity(for: state)
        }
    }
    
    // Helper function to convert TrafficLightState to TrafficLightActivityState
    private func convertToActivityState(_ state: TrafficLightState) -> TrafficLightActivityState {
        switch state {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .off: return .off
        }
    }
    
    // Update or create LiveActivity
    private func updateLiveActivity(for state: TrafficLightState) {
        Task { @MainActor in
            let activityState = convertToActivityState(state)
            
            if activityManager.currentActivity != nil {
                // Update existing activity
                activityManager.updateTrafficLightState(activityState, locationContext: "Current Location")
            } else {
                // Start new activity
                activityManager.startTrafficLightActivity(state: activityState, locationContext: "Current Location")
            }
        }
    }
    
    // Sound and haptic feedback for state changes
    private func playSound(for state: TrafficLightState) {
        let systemSoundID: SystemSoundID
        
        switch state {
        case .red:
            systemSoundID = 1005 // System sound for important alert
        case .yellow:
            systemSoundID = 1053 // System sound for warning/attention
        case .green:
            systemSoundID = 1000 // System sound for success/go
        case .off:
            systemSoundID = 1104 // System sound for power off
        }
        
        // Play system sound with reduced volume for background audio compatibility
        AudioServicesPlaySystemSound(systemSoundID)
        
        // Add haptic feedback for enhanced user experience
        playHapticFeedback(for: state)
    }
    
    private func playHapticFeedback(for state: TrafficLightState) {
        let lightImpactFeedback = UIImpactFeedbackGenerator(style: .light)
        let mediumImpactFeedback = UIImpactFeedbackGenerator(style: .medium)
        let heavyImpactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        let notificationFeedback = UINotificationFeedbackGenerator()
        
        switch state {
        case .red:
            // Strong feedback for stop/warning
            heavyImpactFeedback.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notificationFeedback.notificationOccurred(.error)
            }
        case .yellow:
            // Medium feedback for caution
            mediumImpactFeedback.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notificationFeedback.notificationOccurred(.warning)
            }
        case .green:
            // Light positive feedback for go
            lightImpactFeedback.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notificationFeedback.notificationOccurred(.success)
            }
        case .off:
            // Very light feedback for neutral state
            lightImpactFeedback.impactOccurred()
        }
    }
    
    func cycleStates() {
        Task {
            // Start with red light
            setState(.red)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Move to yellow
            setState(.yellow)
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            
            // Move to green
            setState(.green)
            try await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            
            // Back to off state
            setState(.off)
        }
    }
    
    func manualStateChange() {
        // Manual state cycling for testing/demo purposes
        let nextState: TrafficLightState
        switch currentState {
        case .off:
            nextState = .red
        case .red:
            nextState = .yellow
        case .yellow:
            nextState = .green
        case .green:
            nextState = .off
        }
        setState(nextState)
    }
    
    private func updateTrafficLight() {
        // Start with a random state or default state
        let states: [TrafficLightState] = [.red, .yellow, .green, .off]
        setState(states.randomElement() ?? .off)
    }
    
    private func updateMessage() {
        guard let messages = aiMessages[currentState] else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            aiMessage = messages.randomElement() ?? ""
        }
    }
    
    private func updateAnimation() {
        isAnimating = currentState != .off
    }
}

// Extension to easily integrate with navigation states
extension TrafficLightView {
    func updateForNavigationState(isNavigating: Bool, hasRoute: Bool, isCalculating: Bool) {
        // Only update states when actively navigating
        if isNavigating {
            if isCalculating {
                setState(.yellow)
            } else {
                setState(.green)
            }
        } else {
            // Set to off when not navigating (but this won't be visible anyway)
            setState(.off)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        TrafficLightView()
        
        // Preview different states
        TrafficLightView()
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Preview will show red state
                }
            }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}