//
//  LiveActivityManager.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import Foundation
import ActivityKit
import MapKit

@MainActor
class LiveActivityManager: ObservableObject {
    @Published var currentActivity: Activity<NavigationActivityAttributes>?
    @Published var isLiveActivitySupported: Bool = false
    
    init() {
        checkActivitySupport()
        
        // Monitor authorization changes
        Task {
            for await areEnabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                await MainActor.run {
                    self.isLiveActivitySupported = areEnabled
                }
            }
        }
    }
    
    func requestLiveActivityPermission() async {
        #if targetEnvironment(simulator)
        // Running in simulator - permission requests may not work properly
        #endif
        
        let authInfo = ActivityAuthorizationInfo()
        
        // Note: There's no explicit permission request API for Live Activities
        // They are enabled/disabled in Settings > Screen Time > App Activity
        // We can only check the current status
        
        await MainActor.run {
            self.isLiveActivitySupported = authInfo.areActivitiesEnabled
        }
    }
    
    private func checkActivitySupport() {
        let authInfo = ActivityAuthorizationInfo()
        isLiveActivitySupported = authInfo.areActivitiesEnabled
        
        #if targetEnvironment(simulator)
        // Running in simulator - Live Activities have limited functionality
        #endif
        
        // Check if ActivityKit framework is properly linked
        let activityKitAvailable = Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") != nil
        if !activityKitAvailable {
            // ActivityKit framework not properly configured
        }
    }
    
    func startNavigationActivity(
        startLocation: String,
        destinationName: String,
        currentInstruction: String,
        remainingDistance: Double,
        estimatedTimeRemaining: TimeInterval,
        currentStepIndex: Int,
        totalSteps: Int,
        maneuverType: String
    ) {
        guard isLiveActivitySupported else {
            return
        }
        
        // End any existing activity first
        endNavigationActivity()
        
        let attributes = NavigationActivityAttributes(
            startLocation: startLocation,
            destinationName: destinationName
        )
        
        let contentState = NavigationActivityAttributes.ContentState(
            currentInstruction: currentInstruction,
            remainingDistance: remainingDistance,
            estimatedTimeRemaining: estimatedTimeRemaining,
            currentStepIndex: currentStepIndex,
            totalSteps: totalSteps,
            maneuverType: maneuverType,
            destinationName: destinationName
        )
        
        do {
            let activity = try Activity<NavigationActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(30)
                )
            )
            
            self.currentActivity = activity
            
            // Monitor activity updates
            Task {
                for await activityState in activity.activityStateUpdates {
                    if activityState == .dismissed || activityState == .ended {
                        await MainActor.run {
                            self.currentActivity = nil
                        }
                        break
                    }
                }
            }
            
        } catch {
            #if targetEnvironment(simulator)
            // Simulator may not support LiveActivities fully
            #endif
        }
    }
    
    // Remove the debug function to test LiveActivity creation
    
    func updateNavigationActivity(
        currentInstruction: String,
        remainingDistance: Double,
        estimatedTimeRemaining: TimeInterval,
        currentStepIndex: Int,
        totalSteps: Int,
        maneuverType: String,
        destinationName: String
    ) {
        guard let activity = currentActivity else {
            return
        }
        
        let updatedContentState = NavigationActivityAttributes.ContentState(
            currentInstruction: currentInstruction,
            remainingDistance: remainingDistance,
            estimatedTimeRemaining: estimatedTimeRemaining,
            currentStepIndex: currentStepIndex,
            totalSteps: totalSteps,
            maneuverType: maneuverType,
            destinationName: destinationName
        )
        
        Task {
            await activity.update(
                ActivityContent(
                    state: updatedContentState,
                    staleDate: Date().addingTimeInterval(30)
                )
            )
        }
    }
    
    func endNavigationActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            let finalContentState = NavigationActivityAttributes.ContentState(
                currentInstruction: "Navigation completed",
                remainingDistance: 0,
                estimatedTimeRemaining: 0,
                currentStepIndex: activity.content.state.totalSteps,
                totalSteps: activity.content.state.totalSteps,
                maneuverType: "completed",
                destinationName: activity.content.state.destinationName
            )
            
            await activity.end(
                ActivityContent(
                    state: finalContentState,
                    staleDate: Date().addingTimeInterval(5)
                ),
                dismissalPolicy: .after(.now + 5)
            )
            
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }
    
    func dismissNavigationActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }
    
    // Helper method to extract maneuver type from MKRoute.Step
    func getManeuverType(from step: MKRoute.Step) -> String {
        let instruction = step.instructions.lowercased()
        
        if instruction.contains("left") {
            return "left"
        } else if instruction.contains("right") {
            return "right"
        } else if instruction.contains("continue") || instruction.contains("straight") {
            return "straight"
        } else if instruction.contains("merge") {
            return "merge"
        } else if instruction.contains("exit") {
            return "exit"
        } else {
            return "straight"
        }
    }
}