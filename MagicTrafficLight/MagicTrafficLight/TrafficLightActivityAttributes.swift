//
//  TrafficLightActivityAttributes.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 02/11/25.
//

import Foundation
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Traffic Light Live Activity Attributes
struct TrafficLightActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let trafficLightState: TrafficLightLiveState
        let message: String
        let timestamp: Date
        let locationContext: String
    }
    
    let sessionId: String
    let startedAt: Date
}
#endif