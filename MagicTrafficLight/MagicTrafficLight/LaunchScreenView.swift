//
//  LaunchScreenView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 02/11/25.
//

import SwiftUI

struct LaunchScreenView: View {
    @State private var logoScale = 0.3
    @State private var logoOpacity = 0.0
    @State private var isCompleted = false
    
    var onCompletion: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient similar to the app theme
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.green.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Magic Traffic Light Logo
                Image("MagicTrafficLightLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                // App Name
                Text("Magic Traffic Light")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .opacity(logoOpacity)
                
                // Tagline
                Text("Smart Navigation Assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Animate logo appearance
        withAnimation(.easeOut(duration: 0.4)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Complete launch screen quickly for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCompleted = true
            }
            
            // Call completion after fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onCompletion()
            }
        }
    }
}

#Preview {
    LaunchScreenView {
        print("Launch screen completed")
    }
}