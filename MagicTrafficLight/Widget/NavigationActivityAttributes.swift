import ActivityKit
import Foundation

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