//
//  NavigationActivityAttributes.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import Foundation
import ActivityKit
import SwiftUI

struct NavigationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let currentInstruction: String
        let remainingDistance: Double
        let estimatedTimeRemaining: TimeInterval
        let currentStepIndex: Int
        let totalSteps: Int
        let maneuverType: String
        let destinationName: String
    }
    
    let startLocation: String
    let destinationName: String
}

// MARK: - Helper Functions

func formatDistance(_ distance: Double) -> String {
    if distance < 1000 {
        return "\(Int(distance))m"
    } else {
        return String(format: "%.1fkm", distance / 1000)
    }
}

func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time / 60)
    if minutes < 60 {
        return "\(minutes)min"
    } else {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}