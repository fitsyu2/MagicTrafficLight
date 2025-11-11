//
//  TrafficLightLiveActivity.swift
//  WidgetExtension
//
//  Created by Fitrah Syuhada on 02/11/25.
//

import WidgetKit
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit

struct TrafficLightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrafficLightActivityAttributes.self) { context in
            // Lock screen/banner UI
            TrafficLightLockScreenView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded UI - horizontal traffic light focus
                DynamicIslandExpandedRegion(.leading) {
                    // Horizontal traffic lights taking center stage
                    HStack(spacing: 12) {
                        // Red light
                        Circle()
                            .fill(context.state.trafficLightState == .red ? Color.red : Color.red.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .shadow(color: context.state.trafficLightState == .red ? Color.red.opacity(0.5) : Color.clear, radius: 2)
                            .overlay(
                                Circle()
                                    .fill(context.state.trafficLightState == .red ? Color.red.opacity(0.7) : Color.clear)
                                    .frame(width: 20, height: 20)
                            )
                        
                        // Yellow light
                        Circle()
                            .fill(context.state.trafficLightState == .yellow ? Color.yellow : Color.yellow.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .shadow(color: context.state.trafficLightState == .yellow ? Color.yellow.opacity(0.5) : Color.clear, radius: 2)
                            .overlay(
                                Circle()
                                    .fill(context.state.trafficLightState == .yellow ? Color.yellow.opacity(0.7) : Color.clear)
                                    .frame(width: 20, height: 20)
                            )
                        
                        // Green light
                        Circle()
                            .fill(context.state.trafficLightState == .green ? Color.green : Color.green.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .shadow(color: context.state.trafficLightState == .green ? Color.green.opacity(0.5) : Color.clear, radius: 2)
                            .overlay(
                                Circle()
                                    .fill(context.state.trafficLightState == .green ? Color.green.opacity(0.7) : Color.clear)
                                    .frame(width: 20, height: 20)
                            )
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.systemGray6))
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.trafficLightState.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            } compactLeading: {
                // Compact leading - mini traffic light
                VStack(spacing: 1.5) {
                    // Red light
                    Circle()
                        .fill(context.state.trafficLightState == .red ? Color.red : Color.red.opacity(0.2))
                        .frame(width: 8, height: 8)
                    
                    // Yellow light
                    Circle()
                        .fill(context.state.trafficLightState == .yellow ? Color.yellow : Color.yellow.opacity(0.2))
                        .frame(width: 8, height: 8)
                    
                    // Green light
                    Circle()
                        .fill(context.state.trafficLightState == .green ? Color.green : Color.green.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray6))
                )
            } compactTrailing: {
                // Compact trailing
                Text(context.state.trafficLightState.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
            } minimal: {
                // Minimal - tiny traffic light
                VStack(spacing: 0.5) {
                    // Red light
                    Circle()
                        .fill(context.state.trafficLightState == .red ? Color.red : Color.red.opacity(0.3))
                        .frame(width: 4, height: 4)
                    
                    // Yellow light
                    Circle()
                        .fill(context.state.trafficLightState == .yellow ? Color.yellow : Color.yellow.opacity(0.3))
                        .frame(width: 4, height: 4)
                    
                    // Green light
                    Circle()
                        .fill(context.state.trafficLightState == .green ? Color.green : Color.green.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }
}

struct TrafficLightLockScreenView: View {
    let context: ActivityViewContext<TrafficLightActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Dominant horizontal traffic light layout
            HStack(spacing: 20) {
                // Red light - larger and more prominent
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .fill(context.state.trafficLightState == .red ? Color.red : Color.red.opacity(0.15))
                        .frame(width: 42, height: 42)
                        .shadow(color: context.state.trafficLightState == .red ? Color.red.opacity(0.6) : Color.clear, radius: 4)
                        .overlay(
                            Circle()
                                .fill(context.state.trafficLightState == .red ? Color.red.opacity(0.8) : Color.clear)
                                .frame(width: 42, height: 42)
                        )
                }
                
                // Yellow light
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .fill(context.state.trafficLightState == .yellow ? Color.yellow : Color.yellow.opacity(0.15))
                        .frame(width: 42, height: 42)
                        .shadow(color: context.state.trafficLightState == .yellow ? Color.yellow.opacity(0.6) : Color.clear, radius: 4)
                        .overlay(
                            Circle()
                                .fill(context.state.trafficLightState == .yellow ? Color.yellow.opacity(0.8) : Color.clear)
                                .frame(width: 42, height: 42)
                        )
                }
                
                // Green light
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .fill(context.state.trafficLightState == .green ? Color.green : Color.green.opacity(0.15))
                        .frame(width: 42, height: 42)
                        .shadow(color: context.state.trafficLightState == .green ? Color.green.opacity(0.6) : Color.clear, radius: 4)
                        .overlay(
                            Circle()
                                .fill(context.state.trafficLightState == .green ? Color.green.opacity(0.8) : Color.clear)
                                .frame(width: 42, height: 42)
                        )
                }
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemGray6))
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
            )
            
            // Message at the bottom - clean and simple
            VStack(spacing: 4) {
                Text(context.state.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    if #available(iOS 16.1, *) {
        // Create a mock context for preview
        let mockState = TrafficLightActivityAttributes.ContentState(
            trafficLightState: TrafficLightLiveState.green,
            message: "Traffic Light: Go - Preview Mode",
            timestamp: Date(),
            locationContext: "Main Street"
        )
        
        VStack(spacing: 16) {
            Text("Live Activity Preview")
                .font(.headline)
                .padding()
            
            // Show just the visual layout without the full context
            VStack(spacing: 12) {
                // Horizontal traffic light layout
                HStack(spacing: 20) {
                    // Red light
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 42, height: 42)
                    }
                    
                    // Yellow light  
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .fill(Color.yellow.opacity(0.15))
                            .frame(width: 42, height: 42)
                    }
                    
                    // Green light - active
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 42, height: 42)
                            .shadow(color: Color.green.opacity(0.6), radius: 4)
                            .overlay(
                                Circle()
                                    .fill(Color.green.opacity(0.8))
                                    .frame(width: 42, height: 42)
                            )
                    }
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor.systemGray6))
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                )
                
                // Message section
                VStack(spacing: 4) {
                    Text(mockState.message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
        }
    } else {
        Text("Live Activities require iOS 16.1+")
            .foregroundColor(.secondary)
    }
}

#endif
