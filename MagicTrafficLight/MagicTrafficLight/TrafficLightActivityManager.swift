//
//  TrafficLightActivityManager.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 02/11/25.
//

import Foundation
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit
#endif

// Live Activity specific traffic light state (separate from TrafficLightView)
enum TrafficLightActivityState {
    case red
    case yellow
    case green
    case off
}

@MainActor
class TrafficLightActivityManager: ObservableObject {
    #if canImport(ActivityKit)
    @Published var currentActivity: Activity<TrafficLightActivityAttributes>?
    @Published var activityState: ActivityState = .ended
    #endif
    
    init() {
        #if canImport(ActivityKit)
        // Check for existing activities on startup
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            if let activity = Activity<TrafficLightActivityAttributes>.activities.first {
                self.currentActivity = activity
                self.activityState = activity.activityState
                
                // Monitor activity state changes
                Task {
                    for await state in activity.activityStateUpdates {
                        self.activityState = state
                        if state == .ended || state == .dismissed {
                            self.currentActivity = nil
                        }
                    }
                }
            }
        }
        #endif
    }
    
    // Helper function to convert TrafficLightActivityState to TrafficLightLiveState
    private func convertToLiveState(_ state: TrafficLightActivityState) -> TrafficLightLiveState {
        switch state {
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .off:
            return .off
        }
    }
    
    // Helper function to get message for traffic light state
    private func getTrafficLightMessage(for state: TrafficLightLiveState) -> String {
        switch state {
        case .red:
            return "🛑 Please wait - Traffic Light is Red"
        case .yellow:
            return "⚠️ Prepare to proceed - Traffic Light is Yellow"
        case .green:
            return "✅ Go ahead - Traffic Light is Green"
        case .off:
            return "⚫ Traffic Light is Off"
        }
    }
    
    func startTrafficLightActivity(state: TrafficLightActivityState, locationContext: String = "Current Location") {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }
        
        // End any existing traffic light activity first
        endTrafficLightActivity()
        
        let liveState = convertToLiveState(state)
        let attributes = TrafficLightActivityAttributes(
            sessionId: UUID().uuidString,
            startedAt: Date()
        )
        
        let contentState = TrafficLightActivityAttributes.ContentState(
            trafficLightState: liveState,
            message: getTrafficLightMessage(for: liveState),
            timestamp: Date(),
            locationContext: locationContext
        )
        
        do {
            let activity = try Activity<TrafficLightActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
            
            self.currentActivity = activity
            self.activityState = activity.activityState
            
            print("✅ Traffic Light Live Activity started successfully")
            
            // Monitor activity state changes
            Task {
                for await state in activity.activityStateUpdates {
                    self.activityState = state
                    if state == .ended || state == .dismissed {
                        self.currentActivity = nil
                    }
                }
            }
            
        } catch {
            print("❌ Failed to start Traffic Light Live Activity: \(error)")
        }
        #else
        print("⚠️ ActivityKit not available - Live Activities not supported")
        #endif
    }
    
    func updateTrafficLightState(_ state: TrafficLightActivityState, locationContext: String = "Current Location") {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else {
            print("❌ No active Traffic Light Live Activity to update")
            return
        }
        
        let liveState = convertToLiveState(state)
        let contentState = TrafficLightActivityAttributes.ContentState(
            trafficLightState: liveState,
            message: getTrafficLightMessage(for: liveState),
            timestamp: Date(),
            locationContext: locationContext
        )
        
        Task {
            do {
                await activity.update(.init(state: contentState, staleDate: nil))
                print("✅ Traffic Light Live Activity updated to: \(liveState.displayName)")
            } catch {
                print("❌ Failed to update Traffic Light Live Activity: \(error)")
            }
        }
        #else
        print("⚠️ ActivityKit not available - Live Activities not supported")
        #endif
    }
    
    func endTrafficLightActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else {
            print("ℹ️ No active Traffic Light Live Activity to end")
            return
        }
        
        Task {
            do {
                await activity.end(nil, dismissalPolicy: .immediate)
                print("✅ Traffic Light Live Activity ended")
                self.currentActivity = nil
                self.activityState = .ended
            } catch {
                print("❌ Failed to end Traffic Light Live Activity: \(error)")
            }
        }
        #else
        print("⚠️ ActivityKit not available - Live Activities not supported")
        #endif
    }
    
    func endAllTrafficLightActivities() {
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<TrafficLightActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self.currentActivity = nil
            self.activityState = .ended
            print("✅ All Traffic Light Live Activities ended")
        }
        #else
        print("⚠️ ActivityKit not available - Live Activities not supported")
        #endif
    }
}