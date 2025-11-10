import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            NavigationLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: getSystemImageName(for: context.state.maneuverType))
                            .foregroundColor(.blue)
                        Text(context.state.currentInstruction)
                            .lineLimit(2)
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(formatDistance(context.state.remainingDistance))
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text(formatTime(context.state.estimatedTimeRemaining))
                            .font(.caption2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        Text(context.state.destinationName)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Step \(context.state.currentStepIndex)/\(context.state.totalSteps)")
                                .font(.caption2)
                            Spacer()
                            Text("ETA: \(formatTime(context.state.estimatedTimeRemaining))")
                                .font(.caption2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: getSystemImageName(for: context.state.maneuverType))
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(formatDistance(context.state.remainingDistance))
                    .font(.caption2)
                    .fontWeight(.semibold)
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

@available(iOS 16.1, *)
struct NavigationLiveActivityView: View {
    let context: ActivityViewContext<NavigationActivityAttributes>
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: getSystemImageName(for: context.state.maneuverType))
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.currentInstruction)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    Text("To: \(context.state.destinationName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDistance(context.state.remainingDistance))
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text(formatTime(context.state.estimatedTimeRemaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("Step \(context.state.currentStepIndex) of \(context.state.totalSteps)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("ETA: \(formatTime(context.state.estimatedTimeRemaining))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.blue)
    }
}

// Helper functions
private func getSystemImageName(for maneuverType: String) -> String {
    switch maneuverType.lowercased() {
    case "left", "turn-left", "sharp-left":
        return "arrow.turn.up.left"
    case "right", "turn-right", "sharp-right":
        return "arrow.turn.up.right"
    case "straight", "continue":
        return "arrow.up"
    case "u-turn":
        return "arrow.uturn.left"
    case "merge":
        return "arrow.triangle.merge"
    case "fork":
        return "arrow.triangle.branch"
    case "roundabout":
        return "arrow.triangle.capsulepath"
    case "exit", "off-ramp":
        return "arrow.turn.up.right"
    default:
        return "location.fill"
    }
}

private func formatDistance(_ distance: Double) -> String {
    let formatter = MeasurementFormatter()
    formatter.unitStyle = .short
    formatter.numberFormatter.maximumFractionDigits = 1
    
    if distance < 1000 {
        return formatter.string(from: Measurement(value: distance, unit: UnitLength.meters))
    } else {
        return formatter.string(from: Measurement(value: distance / 1000, unit: UnitLength.kilometers))
    }
}

private func formatTime(_ timeInterval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: timeInterval) ?? "0m"
}

#Preview("Notification", as: .content, using: NavigationActivityAttributes(startLocation: "Current Location", destinationName: "Apple Park")) {
    NavigationLiveActivity()
} contentStates: {
    NavigationActivityContentState(
        currentInstruction: "Turn right onto Infinite Loop",
        remainingDistance: 1500.0,
        estimatedTimeRemaining: 180.0,
        currentStepIndex: 3,
        totalSteps: 8,
        maneuverType: "right",
        destinationName: "Apple Park"
    )
}