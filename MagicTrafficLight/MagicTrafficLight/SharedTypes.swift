//
//  SharedTypes.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 04/11/25.
//

import Foundation
import SwiftUI

enum TrafficLightState {
    case red
    case yellow
    case green
    case off
}

// MARK: - Traffic Light Live Activity State
enum TrafficLightLiveState: String, Codable, CaseIterable {
    case red = "red"
    case yellow = "yellow" 
    case green = "green"
    case off = "off"
    
    var emoji: String {
        switch self {
        case .red: return "🔴"
        case .yellow: return "🟡"
        case .green: return "🟢"
        case .off: return "⚫"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .red: return "circle.fill"
        case .yellow: return "circle.fill"
        case .green: return "circle.fill"
        case .off: return "circle"
        }
    }
    
    var color: Color {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .off: return .gray
        }
    }
    
    var displayName: String {
        switch self {
        case .red: return "Stop"
        case .yellow: return "Caution"
        case .green: return "Go"
        case .off: return "Inactive"
        }
    }
}

// MARK: - Helper Functions

func getTrafficLightMessage(for state: TrafficLightLiveState) -> String {
    switch state {
    case .red:
        return "🛑 Traffic Light: Stop"
    case .yellow:
        return "⚠️ Traffic Light: Caution"
    case .green:
        return "✅ Traffic Light: Go"
    case .off:
        return "⚫ Traffic Light: Inactive"
    }
}