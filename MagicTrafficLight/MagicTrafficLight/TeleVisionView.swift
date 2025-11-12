//
//  TeleVisionView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 02/11/25.
//

import SwiftUI
import Foundation

#if os(iOS)
import UIKit
#endif
import Foundation
import Combine
import AVFoundation
import VideoToolbox
import CoreVideo
import CoreLocation

// MARK: - WebSocket Help Request Manager
class WebSocketHelpManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let helpWebSocketURL: URL
    
    // Callback for help acceptance/rejection
    var onHelpResponse: ((String) -> Void)?
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    // Simple message structure that only sends required fields
    struct SimpleWebSocketMessage: Codable {
        let type: String
        let data: SimpleData
        
        struct SimpleData: Codable {
            let userId: String?
        }
    }
    
    // WebSocket message types - matching server structure
    struct WebSocketMessage: Codable {
        let type: String
        let data: Data
        
        struct Data: Codable {
            // Help Request fields
            let id: String?
            let from: String?
            let to: String?
            let location: Location?
            let message: String?
            
            // Response fields
            let requestId: String?
            let accepted: Bool?
            let helperId: String?
            
            // User fields
            let userId: String?
            
            struct Location: Codable {
                let lat: Double
                let lng: Double
            }
        }
    }
    
    init(serverURL: String = "wss://magictrafficlight-production-b5ed.up.railway.app") {
        // Construct WebSocket URL for help requests
        self.helpWebSocketURL = URL(string: "\(serverURL)/ws/help")!
        print("🔗 WebSocketHelpManager initialized with URL: \(self.helpWebSocketURL)")
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func connect() {
        print("🔗 WebSocketHelpManager: Attempting to connect to \(helpWebSocketURL)")
        connectionStatus = .connecting
        
        webSocketTask = urlSession?.webSocketTask(with: helpWebSocketURL)
        webSocketTask?.resume()
        
        // Note: receiveMessage() will be called from didOpenWithProtocol delegate method
        
        // Set a connection timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if self.connectionStatus == .connecting {
                print("🔴 WebSocket connection timeout")
                self.connectionStatus = .error("Connection timeout")
                self.disconnect()
            }
        }
    }
    
    func disconnect() {
        print("🔗 WebSocketHelpManager: Disconnecting")
        
        // First, mark as disconnected to stop receive loop
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = .disconnected
        }
        
        // Then cancel the WebSocket task
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    @MainActor
    func sendHelpRequest(location: CLLocation?, navigationManager: NavigationManager) {
        guard isConnected else {
            print("🔴 Cannot send help request - not connected")
            return
        }
        
        let userId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-user"
        
        // Prepare location data
        var locationData: [String: Any]?
        if let location = location {
            locationData = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        }
        
        // Prepare route waypoints if navigation is active
        var routeData: [String: Any]?
        if navigationManager.isNavigating, let route = navigationManager.currentRoute {
            var waypointsData: [[String: Any]] = []
            
            // Add all route steps as waypoints
            for (index, step) in route.steps.enumerated() {
                let coordinate = step.polyline.coordinate
                let waypointData: [String: Any] = [
                    "stepIndex": index,
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                    "instructions": step.instructions,
                    "distance": step.distance,
                    "isCurrentStep": index == navigationManager.currentStepIndex
                ]
                waypointsData.append(waypointData)
            }
            
            // Add destination information
            var destinationData: [String: Any]?
            if let destination = navigationManager.destination {
                destinationData = [
                    "name": destination.name ?? "Unknown Destination",
                    "latitude": destination.placemark.coordinate.latitude,
                    "longitude": destination.placemark.coordinate.longitude,
                    "address": destination.placemark.title ?? ""
                ]
            }
            
            routeData = [
                "isNavigating": true,
                "currentStepIndex": navigationManager.currentStepIndex,
                "totalSteps": route.steps.count,
                "remainingDistance": navigationManager.remainingDistance,
                "estimatedTimeRemaining": navigationManager.estimatedTimeRemaining,
                "waypoints": waypointsData,
                "destination": destinationData ?? [:]
            ]
        }
        
        // Create comprehensive help request data
        var helpRequestData: [String: Any] = [
            "from": userId,
            "message": "Help needed from MagicTrafficLight user",
            "deviceInfo": [
                "model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            ]
        ]
        
        // Add location if available
        if let locationData = locationData {
            helpRequestData["location"] = locationData
        }
        
        // Add route information if available
        if let routeData = routeData {
            helpRequestData["route"] = routeData
        } else {
            helpRequestData["route"] = [
                "isNavigating": false
            ]
        }
        
        let helpRequestMessage: [String: Any] = [
            "type": "help_request",
            "data": helpRequestData
        ]
        
        // Send as JSON directly
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: helpRequestMessage)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            print("📤 Sending help request JSON: \(jsonString)")
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("🔴 Failed to send help request: \(error)")
                } else {
                    print("✅ Help request sent successfully")
                }
            }
        } catch {
            print("🔴 Failed to encode help request: \(error)")
        }
    }
    
    private func sendMessage(_ message: WebSocketMessage) {
        do {
            let data = try JSONEncoder().encode(message)
            let jsonString = String(data: data, encoding: .utf8)!
            
            // Debug: Print the exact JSON being sent
            print("📤 Sending JSON: \(jsonString)")
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("🔴 Failed to send message: \(error)")
                } else {
                    print("✅ Message sent successfully: \(message.type)")
                }
            }
        } catch {
            print("🔴 Failed to encode message: \(error)")
        }
    }
    
    private func sendSimpleMessage(_ message: SimpleWebSocketMessage) {
        do {
            let data = try JSONEncoder().encode(message)
            let jsonString = String(data: data, encoding: .utf8)!
            
            // Debug: Print the exact JSON being sent
            print("📤 Sending Simple JSON: \(jsonString)")
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("🔴 Failed to send simple message: \(error)")
                } else {
                    print("✅ Simple message sent successfully: \(message.type)")
                }
            }
        } catch {
            print("🔴 Failed to encode simple message: \(error)")
        }
    }
    
    @MainActor
    func sendLocationUpdate(location: CLLocation) {
        guard isConnected else {
            print("🔴 Cannot send location update - not connected")
            return
        }
        
        let userId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-user"
        
        let locationUpdateMessage: [String: Any] = [
            "type": "location_update",
            "data": [
                "userId": userId,
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                "speed": location.speed >= 0 ? location.speed : 0, // Only include if valid
                "heading": location.course >= 0 ? location.course : 0 // Only include if valid
            ]
        ]
        
        // Send as JSON directly
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: locationUpdateMessage)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            print("📍 Sending location update: lat=\(String(format: "%.6f", location.coordinate.latitude)), lng=\(String(format: "%.6f", location.coordinate.longitude))")
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("🔴 Failed to send location update: \(error)")
                } else {
                    print("✅ Location update sent successfully")
                }
            }
        } catch {
            print("🔴 Failed to encode location update: \(error)")
        }
    }

    deinit {
        disconnect()
    }
}

// MARK: - WebSocket Delegate Extension
extension WebSocketHelpManager: URLSessionDelegate, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected successfully to \(helpWebSocketURL)")
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = .connected
            self.lastError = nil
        }
        
        // Register user immediately after connection
        registerUser()
    }
    
    private func registerUser() {
        let userId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-user"
        
        // Use simple message format to avoid null field issues
        let userJoinedMessage = SimpleWebSocketMessage(
            type: "user_joined",
            data: SimpleWebSocketMessage.SimpleData(userId: userId)
        )
        
        sendSimpleMessage(userJoinedMessage)
        
        // Start listening for messages
        receiveMessage()
    }
    
    private func receiveMessage() {
        // Check if we're still connected before trying to receive
        guard let task = webSocketTask, isConnected else {
            print("🔗 receiveMessage: WebSocket not connected, stopping receive loop")
            return
        }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            // Double-check connection status when callback executes
            guard self.isConnected else {
                print("🔗 receiveMessage callback: WebSocket disconnected, stopping receive loop")
                return
            }
            
            switch result {
            case .success(let message):
                self.handleIncomingMessage(message)
                // Continue listening for more messages only if still connected
                if self.isConnected {
                    self.receiveMessage()
                }
            case .failure(let error):
                print("🔴 Failed to receive message: \(error)")
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.connectionStatus = .error(error.localizedDescription)
                    self.isConnected = false
                }
            }
        }
    }
    
    private func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("📱 Received WebSocket message: \(text)")
            // Try to parse as JSON to handle different message types
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messageType = json["type"] as? String {
                
                print("📱 Processing message type: '\(messageType)'")
                switch messageType {
                case "help_submitted":
                    print("📱 Help request submitted successfully")
                case "help_request_response":
                    print("📱 Received help request response")
                case "help_request_accepted":
                    print("📱 Help request accepted!")
                    handleHelpAccepted()
                case "status_update":
                    if let statusData = json["data"] as? [String: Any],
                       let connectedUsers = statusData["connected_users"] as? Int,
                       let pendingRequests = statusData["pending_requests"] as? Int {
                        print("📊 Status update: \(connectedUsers) users connected, \(pendingRequests) pending requests")
                    }
                case "requests_cleared":
                    if let clearData = json["data"] as? [String: Any],
                       let clearedCount = clearData["clearedCount"] as? Int,
                       let message = clearData["message"] as? String {
                        print("📱 Server cleared requests: \(message), count: \(clearedCount)")
                    }
                case "user_joined_ack":
                    print("📱 User joined acknowledgment received")
                case "error":
                    if let errorData = json["data"] as? [String: String],
                       let errorMessage = errorData["error"] {
                        print("📱 Server error: \(errorMessage)")
                    }
                default:
                    print("📱 Unknown message type: \(messageType)")
                }
            } else {
                // Handle plain text messages
                print("📱 Received plain text: \(text)")
            }
        case .data(let data):
            print("📱 Received binary WebSocket message: \(data.count) bytes")
        @unknown default:
            break
        }
    }
    
    private func handleHelpAccepted() {
        print("🎉 Help request accepted!")
        onHelpResponse?("accepted")
    }
    
    private func handleHelpRejected() {
        print("❌ Help request rejected")
        onHelpResponse?("rejected")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔗 WebSocket closed with code: \(closeCode)")
        if let reasonData = reason, let reasonString = String(data: reasonData, encoding: .utf8) {
            print("🔗 Close reason: \(reasonString)")
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = .disconnected
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("🔗 WebSocket task completed with error: \(error)")
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Apple Intelligence Availability Check
@available(iOS 18.1, *)
@available(iOS 18.1, *)
class AppleIntelligenceChecker: ObservableObject {
    @Published var isAvailable = false
    @Published var hasChecked = false
    
    init() {
        checkAvailability()
    }
    
    func checkAvailability() {
        DispatchQueue.global(qos: .background).async {
            // Check device capabilities - using processor count as a proxy
            let _ = UIDevice.current.name
            let _ = UIDevice.current.model
            let processorCount = ProcessInfo.processInfo.processorCount
            
            // Simple heuristic: devices with more processors are more likely to support AI
            let hasCapableHardware = processorCount >= 6
            
            DispatchQueue.main.async {
                self.isAvailable = hasCapableHardware
                self.hasChecked = true
            }
        }
    }
}

// MARK: - Frame Streaming Manager
class FrameStreamManager: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var currentFrame: UIImage?
    @Published var isStreaming = false
    @Published var connectionStatus: StreamStatus = .disconnected
    @Published var frameRate: Double = 0.0
    
    private var frameBuffer: [UIImage] = []
    private let maxBufferSize = 10
    private var yuvBuffer = Data()
    private var frameHeader: YUV420FrameHeader?
    private var expectedFrameSize: Int = 0
    
    // Session and task management
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var dataTask: URLSessionDataTask?
    private var frameTimer: Timer?
    
    // Track delayed operations for cleanup
    private var timeoutWorkItem: DispatchWorkItem?
    
    // Frame rate calculation
    private var frameCount = 0
    private var lastSuccessfulFrame: UIImage?
    private var lastFrameTime = Date()
    
    // Connection state
    private var isConnecting = false
    private var isAndroidPolling = false // Track if we're using Android polling
    
    enum StreamStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case buffering
        case streaming
        case error(String)
    }
    
    enum StreamType {
        case webSocket(URL)
        case http(URL)
        case yuv420(URL)
        case androidPolling(URL)  // New: HTTP polling for Android RGBA frames
    }
    
    struct YUV420FrameHeader {
        let width: UInt32
        let height: UInt32
        let ySize: UInt32
        let uSize: UInt32
        let vSize: UInt32
        let totalSize: UInt32
        
        static let headerSize = 20 // 5 * 4 bytes for UInt32 values (server sends 5 fields)
        
        init?(from data: Data) {
            guard data.count >= Self.headerSize else { return nil }
            
            // Read as big endian to match server
            self.width = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
            self.height = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).bigEndian }
            self.ySize = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).bigEndian }
            self.uSize = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self).bigEndian }
            self.vSize = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self).bigEndian }
            
            // Validate that the values are reasonable before calculating total size
            guard width > 0 && width < 10000,
                  height > 0 && height < 10000,
                  ySize > 0 && ySize < 100_000_000,
                  uSize > 0 && uSize < 100_000_000,
                  vSize > 0 && vSize < 100_000_000 else {
                print("📡 Invalid YUV420 header values: \(width)x\(height), Y:\(ySize), U:\(uSize), V:\(vSize)")
                return nil
            }
            
            // Use safe addition to prevent overflow
            let (yPlusU, yPlusUOverflow) = ySize.addingReportingOverflow(uSize)
            let (total, totalOverflow) = yPlusU.addingReportingOverflow(vSize)
            
            guard !yPlusUOverflow && !totalOverflow else {
                print("📡 YUV420 header calculation overflow: Y:\(ySize) + U:\(uSize) + V:\(vSize)")
                return nil
            }
            
            self.totalSize = total
        }
    }
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // Increased from 30 to 60 seconds
        config.timeoutIntervalForResource = 0 // No timeout for continuous streams
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func cleanupURLSession() {
        // First invalidate to stop all delegate callbacks
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        // Then cancel individual tasks
        dataTask?.cancel()
        dataTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    func startStreaming(from url: URL, type: StreamType? = nil) {
        print("📡 🚀 FrameStreamManager: Starting stream from \(url)")
        print("📡 🔍 URL Analysis:")
        print("📡   - Scheme: \(url.scheme ?? "nil")")
        print("📡   - Host: \(url.host ?? "nil")")
        print("📡   - Path: \(url.path)")
        print("📡   - Absolute String: \(url.absoluteString)")
        
        isConnecting = true
        
        // Auto-detect stream type based on URL if not specified
        let streamType = type ?? detectStreamType(from: url)
        
        print("📡 🎯 Stream type determined: \(streamType)")
        
        switch streamType {
        case .webSocket(let wsUrl):
            print("📡 🌐 Using WebSocket stream for H.264")
            print("📡 🎥 This should receive H.264 frames!")
            startWebSocketStream(url: wsUrl)
        case .androidPolling(let pollingUrl):
            print("📡 📱 Using Android HTTP polling for RGBA frames")
            print("📡 🎨 This will poll for Android RGBA_8888 frames!")
            startAndroidPolling(url: pollingUrl)
        case .http(let httpUrl):
            print("📡 🌍 Using HTTP stream")
            startHTTPStream(url: httpUrl)
        case .yuv420(let yuvUrl):
            print("📡 📺 Using YUV420 stream")
            startYUV420Stream(url: yuvUrl)
        }
    }
    
    private func detectStreamType(from url: URL) -> StreamType {
        let urlString = url.absoluteString.lowercased()
        
        print("📡 🕵️ Detecting stream type for URL: \(urlString)")
        
        if urlString.contains("ws://") || urlString.contains("wss://") {
            print("📡 ✅ Detected WebSocket URL - returning .webSocket type")
            return .webSocket(url)
        } else if urlString.contains("/api/android/frame") {
            print("📡 ✅ Detected Android polling URL - returning .androidPolling type")
            return .androidPolling(url)
        } else if urlString.contains("yuv420") || urlString.contains("yuv") {
            print("📡 ✅ Detected YUV URL - returning .yuv420 type")
            return .yuv420(url)
        } else {
            print("📡 ⚠️ No specific type detected - defaulting to .yuv420 type")
            // Default to YUV420 for HTTP streams
            return .yuv420(url)
        }
    }
    
    func stopStreaming() {
        print("📡 Stopping stream - clearing all resources")
        
        // First stop streaming to prevent new frames
        isStreaming = false
        
        // Clear current frame immediately to stop Metal rendering
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrame = nil
        }
        
        connectionStatus = .disconnected
        
        // Cancel timers and delayed operations
        frameTimer?.invalidate()
        frameTimer = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        
        // Clean up URLSession and network tasks
        cleanupURLSession()
        
        // Recreate URLSession for future use
        setupURLSession()
        
        // Clear all buffers and state
        yuvBuffer.removeAll()
        frameHeader = nil
        expectedFrameSize = 0
        frameBuffer.removeAll()
        frameRate = 0.0
        
        // Force a small delay to ensure Metal operations complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("📡 Stream stopped - all resources cleared")
        }
    }
    
    private func startWebSocketStream(url: URL) {
        print("📡 🚀 Starting WebSocket H.264 stream to: \(url)")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        
        // Add state monitoring for the WebSocket
        print("📡 🔌 WebSocket task created, starting connection...")
        webSocketTask?.resume()
        
        connectionStatus = .connected
        isStreaming = true
        
        print("📡 ✅ WebSocket H.264 stream started, beginning to listen for frames...")
        receiveWebSocketFrame()
    }
    
    private func startAndroidPolling(url: URL) {
        print("📡 🚀 Starting Android RGBA frame polling from: \(url)")
        print("📡 🔍 Full URL: \(url.absoluteString)")
        print("📡 🌐 Host: \(url.host ?? "unknown")")
        print("📡 🛤️ Path: \(url.path)")
        print("📡 ⚡ Will poll every 200ms for 360x640 RGB at 5fps")
        
        connectionStatus = .connected
        isStreaming = true
        isAndroidPolling = true // Set flag to prevent conflicting timers
        
        // Start polling timer - poll every 200ms (5 FPS) to match Android upload rate
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            self.pollAndroidFrame(from: url)
        }
        
        print("📡 ✅ Android polling started successfully")
        
        // Also do an immediate poll to test the connection
        print("📡 🎯 Performing immediate test poll...")
        pollAndroidFrame(from: url)
    }
    
    private func stopAndroidPolling() {
        print("📡 🛑 Stopping Android RGBA frame polling...")
        
        // Stop the timer first
        frameTimer?.invalidate()
        frameTimer = nil
        
        // Update state
        isStreaming = false
        connectionStatus = .disconnected
        
        print("📡 ✅ Android polling stopped successfully")
    }
    
    private func pollAndroidFrame(from url: URL) {
        guard isStreaming else {
            print("📡 ⏹️ Stopping Android polling - streaming disabled")
            return
        }
        
        print("📡 📡 Polling for Android frame from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0 // 5 second timeout
        request.setValue("iOS-MagicTrafficLight/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            let timestamp = DateFormatter().string(from: Date())
            
            if let error = error {
                print("📡 ❌ [\(timestamp)] Android polling error: \(error.localizedDescription)")
                
                // Check for specific error types
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet:
                        print("📡 🔴 No internet connection")
                    case .timedOut:
                        print("📡 ⏱️ Request timed out (server may be down)")
                    case .cannotConnectToHost:
                        print("📡 🏠 Cannot connect to host (server may be down)")
                    case .cannotFindHost:
                        print("📡 🔍 Cannot find host (DNS issue)")
                    default:
                        print("📡 🔗 URL Error: \(urlError.localizedDescription)")
                    }
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("📡 ❌ [\(timestamp)] Invalid response type")
                return
            }
            
            print("📡 📊 [\(timestamp)] HTTP Response: \(httpResponse.statusCode)")
            print("📡 🔍 Response URL: \(httpResponse.url?.absoluteString ?? "unknown")")
            print("📡 📋 Response Headers:")
            for (key, value) in httpResponse.allHeaderFields {
                print("📡    \(key): \(value)")
            }
            
            if httpResponse.statusCode == 200 {
                guard let data = data else {
                    print("📡 ❌ [\(timestamp)] No frame data received despite 200 status")
                    return
                }
                
                print("📡 ✅ [\(timestamp)] Frame received! Data size: \(data.count) bytes")
                
                // Extract metadata from headers
                let width = Int(httpResponse.value(forHTTPHeaderField: "X-Frame-Width") ?? "0") ?? 0
                let height = Int(httpResponse.value(forHTTPHeaderField: "X-Frame-Height") ?? "0") ?? 0
                let format = httpResponse.value(forHTTPHeaderField: "X-Frame-Format") ?? "Unknown"
                let serverTimestamp = httpResponse.value(forHTTPHeaderField: "X-Frame-Timestamp") ?? "0"
                let serverFrameSize = Int(httpResponse.value(forHTTPHeaderField: "X-Frame-Size") ?? "0") ?? 0
                
                // Calculate expected size for RGBA_8888
                let expectedSize = width * height * 4
                
                print("📡 📋 [\(timestamp)] Android frame metadata:")
                print("📡   - Size: \(width)x\(height)")
                print("📡   - Format: \(format)")
                print("📡   - Actual data size: \(data.count) bytes")
                print("📡   - Server frame size header: \(serverFrameSize) bytes")
                print("📡   - Expected size (w×h×4): \(expectedSize) bytes")
                print("📡   - Server timestamp: \(serverTimestamp)")
                
                // Specific check for 360x640 RGB @ 5fps configuration
                if width == 360 && height == 640 {
                    let expected360x640 = 360 * 640 * 4  // = 921,600 bytes
                    print("📡 🎯 360x640 RGB DETECTED:")
                    print("📡   - Expected for 360x640 RGBA: \(expected360x640) bytes")
                    print("📡   - Match status: \(data.count == expected360x640 ? "✅ PERFECT" : "❌ MISMATCH")")
                }
                
                // Detailed size analysis with FIXED SERVER NOTE
                if data.count == expectedSize && serverFrameSize == expectedSize {
                    print("📡 ✅ PERFECT MATCH: All size calculations agree! Header parsing fix worked!")
                } else if data.count != expectedSize {
                    print("📡 🔍 Size Analysis:")
                    print("📡   - Difference: \(data.count - expectedSize) bytes")
                    print("📡   - Ratio: \(String(format: "%.3f", Double(data.count) / Double(expectedSize)))")
                    
                    if data.count > expectedSize {
                        print("📡   - Data is LARGER than expected (may have headers/padding)")
                    } else {
                        print("📡   - Data is SMALLER than expected (may be incomplete)")
                    }
                }
                
                if serverFrameSize != data.count {
                    print("📡 ⚠️ Server header mismatch: server says \(serverFrameSize), got \(data.count)")
                }
                
                if serverFrameSize == expectedSize {
                    print("📡 ✅ Server calculation CORRECT: \(serverFrameSize) = \(expectedSize) (header parsing works!)")
                } else if serverFrameSize != expectedSize {
                    print("📡 ❌ Server calculation mismatch: server calculated \(serverFrameSize), we calculated \(expectedSize)")
                    print("📡 🔧 This suggests server header parsing may still have issues")
                }
                
                // Validate basic requirements
                guard width > 0 && height > 0 else {
                    print("📡 ❌ Invalid frame dimensions: \(width)x\(height)")
                    return
                }
                
                guard data.count >= expectedSize else {
                    print("📡 ❌ Insufficient data: need at least \(expectedSize) bytes for \(width)x\(height) RGBA")
                    return
                }
                
                // Try to convert even if sizes don't match exactly (use expected size)
                let frameData = data.count > expectedSize ? data.prefix(expectedSize) : data
                print("📡 🎨 Converting frame data: using \(frameData.count) bytes for \(width)x\(height)")
                
                // Convert RGBA data to UIImage - try server dimensions first
                if let image = self.createImageFromRGBAData(Data(frameData), width: width, height: height) {
                    print("📡 ✅ Successfully converted RGBA data to UIImage using server dimensions \(width)x\(height)")
                    DispatchQueue.main.async {
                        self.addFrameToBuffer(image)
                        self.lastSuccessfulFrame = image
                        if self.connectionStatus != .streaming {
                            self.connectionStatus = .streaming
                        }
                        print("📡 🖼️ Frame displayed in UI!")
                    }
                } else {
                    print("📡 ❌ Failed to convert RGBA data using server dimensions \(width)x\(height)")
                    print("📡 🔧 Trying calculated dimensions based on actual data size...")
                    
                    // Try to calculate dimensions from actual data size
                    let actualDataSize = data.count
                    let possibleDimensions = self.calculatePossibleDimensions(dataSize: actualDataSize)
                    
                    var conversionSuccess = false
                    for (w, h) in possibleDimensions {
                        print("📡 🧮 Trying dimensions: \(w)x\(h)")
                        if let image = self.createImageFromRGBAData(Data(frameData), width: w, height: h) {
                            print("📡 ✅ SUCCESS with calculated dimensions \(w)x\(h)")
                            DispatchQueue.main.async {
                                self.addFrameToBuffer(image)
                                self.lastSuccessfulFrame = image
                                if self.connectionStatus != .streaming {
                                    self.connectionStatus = .streaming
                                }
                                print("📡 🖼️ Frame displayed with calculated dimensions!")
                            }
                            conversionSuccess = true
                            break
                        }
                    }
                    
                    if !conversionSuccess {
                        print("📡 ❌ Failed to convert RGBA data with any calculated dimensions")
                    }
                }
                
            } else if httpResponse.statusCode == 404 {
                // No frame available - this is normal, just continue polling
                print("📡 ℹ️ [\(timestamp)] No Android frame available (404) - this is normal")
                
                // Check if this is the first time we're seeing 404s
                if self.connectionStatus != .connected && self.connectionStatus != .streaming {
                    print("📡 📡 Server is responding but no frames uploaded yet")
                    DispatchQueue.main.async {
                        self.connectionStatus = .connected
                    }
                }
            } else {
                print("📡 ❌ [\(timestamp)] Unexpected HTTP status: \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    print("📡 📄 Response body: \(responseBody)")
                }
            }
            
        }.resume()
    }
    
    private func createImageFromRGBAData(_ data: Data, width: Int, height: Int) -> UIImage? {
        print("📡 🎨 Converting RGBA data to UIImage: \(width)x\(height), \(data.count) bytes")
        
        guard width > 0 && height > 0 else {
            print("📡 ❌ Invalid dimensions: \(width)x\(height)")
            return nil
        }
        
        let expectedSize = width * height * 4 // RGBA = 4 bytes per pixel
        
        // Specific validation for 360x640 @ 5fps configuration
        if width == 360 && height == 640 {
            let expected360x640 = 921600 // 360 * 640 * 4
            print("📡 🎯 Processing 360x640 RGB frame:")
            print("📡   - Expected: \(expected360x640) bytes")
            print("📡   - Received: \(data.count) bytes")
            print("📡   - Status: \(data.count == expected360x640 ? "✅ Perfect match!" : "⚠️ Size mismatch")")
        }
        
        guard data.count >= expectedSize else {
            print("📡 ❌ Insufficient RGBA data: need \(expectedSize), got \(data.count)")
            return nil
        }
        
        // Create a CGImage from RGBA data
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            print("📡 ❌ Failed to create CGImage from RGBA data")
            return nil
        }
        
        let image = UIImage(cgImage: cgImage)
        print("📡 ✅ Successfully created UIImage: \(image.size)")
        return image
    }
    
    private func calculatePossibleDimensions(dataSize: Int) -> [(width: Int, height: Int)] {
        print("📡 🧮 Calculating possible dimensions for \(dataSize) bytes")
        
        let pixelCount = dataSize / 4 // RGBA = 4 bytes per pixel
        var possibilities: [(Int, Int)] = []
        
        // Based on the 60% ratio (4,976,640 vs 8,294,400), let's try some common dimensions
        // that might result in this exact data size
        
        // Calculate what dimensions would give us exactly this data size
        let exactPixels = dataSize / 4
        print("📡 🔢 Exact pixel count: \(exactPixels)")
        
        // Try to find integer square root approximations
        let sqrtValue = Double(exactPixels).squareRoot()
        print("📡 📐 Square root: \(sqrtValue)")
        
        // Common aspect ratios that might fit
        let aspectRatios: [(Double, Double)] = [
            (1.0, 1.0),     // 1:1 square
            (4.0, 3.0),     // 4:3 traditional
            (16.0, 9.0),    // 16:9 widescreen
            (3.0, 2.0),     // 3:2 photo
            (5.0, 4.0),     // 5:4
            (16.0, 10.0),   // 16:10
            (1.33, 1.0),    // ~4:3
        ]
        
        for (ratioW, ratioH) in aspectRatios {
            // Calculate dimensions for this aspect ratio
            let h = (Double(exactPixels) / (ratioW / ratioH)).squareRoot()
            let w = h * (ratioW / ratioH)
            
            let intW = Int(round(w))
            let intH = Int(round(h))
            
            // Check if this gives us the exact data size
            if intW * intH * 4 == dataSize {
                possibilities.append((intW, intH))
                print("📡 ✅ Found exact match: \(intW)x\(intH) = \(intW * intH) pixels = \(intW * intH * 4) bytes")
            }
        }
        
        // Also try some specific common resolutions that might be close
        let commonResolutions: [(Int, Int)] = [
            (1115, 1115),   // Square that might match
            (1280, 972),    // Calculated from ratio
            (1024, 1214),   // Another possibility
            (960, 1296),    // Another possibility
            (1200, 1037),   // Another possibility
        ]
        
        for (w, h) in commonResolutions {
            let calculatedSize = w * h * 4
            if calculatedSize == dataSize {
                possibilities.append((w, h))
                print("📡 ✅ Common resolution exact match: \(w)x\(h)")
            } else if abs(calculatedSize - dataSize) < 1000 { // Within 1KB
                print("📡 ⚠️ Close match: \(w)x\(h) = \(calculatedSize) bytes (diff: \(calculatedSize - dataSize))")
            }
        }
        
        // If no exact matches, try the closest integer factors
        if possibilities.isEmpty {
            print("📡 🔍 No exact matches found, trying closest factors...")
            
            // Find factors of the pixel count
            var factors: [(Int, Int)] = []
            let maxFactor = Int(sqrtValue) + 100 // Search around the square root
            
            for i in 1...maxFactor {
                if exactPixels % i == 0 {
                    let j = exactPixels / i
                    factors.append((i, j))
                    factors.append((j, i)) // Both orientations
                }
            }
            
            // Sort by how close to square they are (most reasonable aspect ratios first)
            factors.sort { pair1, pair2 in
                let ratio1 = Double(max(pair1.0, pair1.1)) / Double(min(pair1.0, pair1.1))
                let ratio2 = Double(max(pair2.0, pair2.1)) / Double(min(pair2.0, pair2.1))
                return ratio1 < ratio2
            }
            
            // Take the most reasonable aspect ratios (first few)
            possibilities = Array(factors.prefix(5))
            
            print("📡 📊 Best factor pairs:")
            for (i, (w, h)) in possibilities.enumerated() {
                let ratio = Double(max(w, h)) / Double(min(w, h))
                print("📡   \(i + 1). \(w)x\(h) (ratio: \(String(format: "%.2f", ratio)):1)")
            }
        }
        
        return possibilities
    }
    
    private func receiveWebSocketFrame() {
        guard webSocketTask != nil else {
            print("📡 ❌ receiveWebSocketFrame: No WebSocket task available")
            return
        }
        
        guard isStreaming else {
            print("📡 ⏹️ receiveWebSocketFrame: Streaming stopped, not listening for frames")
            return
        }
        
        print("📡 👂 Waiting for WebSocket message...")
        
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { 
                print("📡 ❌ receiveWebSocketFrame callback: self is nil")
                return 
            }
            
            print("📡 📨 WebSocket receive callback triggered")
            
            switch result {
            case .success(let message):
                print("📡 ✅ Successfully received WebSocket message")
                
                switch message {
                case .data(let data):
                    print("📡 📊 Received BINARY data: \(data.count) bytes")
                    print("📡 🔍 Data preview (first 32 bytes): \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    // Handle H.264 frame data with metadata header
                    self.processH264Frame(data)
                case .string(let text):
                    print("📡 📝 Received TEXT message: '\(text)'")
                    if text == "STREAM_START" {
                        print("📡 🚀 Received STREAM_START signal")
                        DispatchQueue.main.async {
                            self.connectionStatus = .streaming
                            self.isStreaming = true
                            self.startFramePlayback()
                        }
                    } else {
                        print("📡 ⚠️ Warning: Expected binary data for H.264, got text: '\(text)'")
                    }
                @unknown default:
                    print("📡 ❓ Received UNKNOWN message type")
                }
                
                // Continue listening for more frames
                if self.isStreaming {
                    print("📡 🔄 Continuing to listen for next frame...")
                    self.receiveWebSocketFrame()
                } else {
                    print("📡 ⏹️ Streaming stopped, not scheduling next receive")
                }
                
            case .failure(let error):
                print("📡 ❌ WebSocket receive failed: \(error)")
                print("📡 🔍 Error details: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connectionStatus = .error("WebSocket receive failed: \(error.localizedDescription)")
                    self.isStreaming = false
                }
            }
        }
    }
    
    private func processH264Frame(_ data: Data) {
        print("📡 🎥 === H.264 FRAME PROCESSING START ===")
        print("📡 📊 Received H.264 frame: \(data.count) bytes")
        
        guard isStreaming && connectionStatus != .disconnected else {
            print("📡 ❌ Ignoring H.264 frame - streaming stopped or disconnected")
            print("📡 🔍 Current state: isStreaming=\(isStreaming), connectionStatus=\(connectionStatus)")
            return
        }
        
        // Parse metadata header (28 bytes) + H.264 frame data
        guard data.count > 28 else {
            print("📡 ❌ H.264 frame too small: \(data.count) bytes (need at least 29 bytes)")
            print("📡 🔍 Data hex dump: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
            return
        }
        
        // Extract metadata header (28 bytes)
        let headerData = data.subdata(in: 0..<28)
        let frameData = data.subdata(in: 28..<data.count)
        
        print("📡 📋 Header data (28 bytes): \(headerData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        print("📡 🎬 Frame data: \(frameData.count) bytes")
        print("📡 🎬 First 16 bytes of frame: \(frameData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // Parse frame metadata
        let width = headerData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let height = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let dataLength = headerData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
        let isKeyFrame = headerData.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) } == 1
        let presentationTime = headerData.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        let frameRate = headerData.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }
        
        print("📡 📐 H.264 Metadata:")
        print("📡   - Width: \(width)")
        print("📡   - Height: \(height)")
        print("📡   - Data Length: \(dataLength)")
        print("📡   - Key Frame: \(isKeyFrame)")
        print("📡   - Presentation Time: \(presentationTime)")
        print("📡   - Frame Rate: \(frameRate)")
        
        // Validate H.264 frame format
        guard frameData.count >= 5 else {
            print("📡 ❌ Invalid H.264 frame size: \(frameData.count) bytes (need at least 5)")
            return
        }
        
        // Check H.264 Annex B start code (0x00000001)
        let startCode = frameData.prefix(4)
        let startCodeHex = startCode.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("📡 🔍 H.264 start code check: \(startCodeHex)")
        
        guard frameData[0] == 0x00 && frameData[1] == 0x00 && 
              frameData[2] == 0x00 && frameData[3] == 0x01 else {
            print("📡 ❌ Invalid H.264 start code. Expected: 00 00 00 01, Got: \(startCodeHex)")
            return
        }
        
        print("📡 ✅ Valid H.264 start code detected")
        
        // Convert H.264 to UIImage using VideoToolbox
        print("📡 🎨 Attempting to decode H.264 frame to UIImage...")
        if let image = decodeH264ToImage(frameData, width: Int(width), height: Int(height)) {
            print("📡 🎉 Successfully created placeholder image for H.264 frame!")
            DispatchQueue.main.async {
                self.addFrameToBuffer(image)
                self.frameRate = Double(frameRate)
                if self.connectionStatus != .streaming {
                    print("📡 🔄 Updating connection status to streaming")
                    self.connectionStatus = .streaming
                }
            }
            print("📡 ✅ Successfully decoded H.264 frame to UIImage")
        } else {
            print("📡 ❌ Failed to decode H.264 frame to UIImage")
        }
        
        print("📡 🎥 === H.264 FRAME PROCESSING END ===\n")
    }
    
    private func startHTTPStream(url: URL) {
        // Implement HTTP polling for frames
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.fetchHTTPFrame(from: url)
        }
        connectionStatus = .streaming
        isStreaming = true
    }
    
    private func fetchHTTPFrame(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.addFrameToBuffer(image)
            }
        }.resume()
    }
    private func startYUV420Stream(url: URL) {
        print("📡 Starting YUV420 stream from: \(url)")
        connectionStatus = .connecting
        yuvBuffer.removeAll()
        frameHeader = nil
        
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("iOS-MagicTrafficLight/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0
        
        dataTask = urlSession?.dataTask(with: request)
        dataTask?.resume()
        print("📡 YUV420 task started")
        
        // Set isStreaming to true when we start the data task
        isStreaming = true
        connectionStatus = .buffering
        
        // Add connection timeout with cancellable work item
        timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.connectionStatus == .connecting || self.connectionStatus == .buffering {
                print("📡 YUV420 connection timeout - stopping")
                self.connectionStatus = .error("Connection timeout")
                self.isStreaming = false
                self.dataTask?.cancel()
            }
        }
        
        if let timeoutWorkItem = timeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
        }
    }
    
    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Early exit if streaming has been stopped or disconnected
        guard isStreaming && connectionStatus != .disconnected else {
            print("📡 Ignoring data - streaming stopped \(isStreaming) \(connectionStatus)")
            return
        }
        
        print("📡 Received \(data.count) bytes of data")
        
        // Update connection status when we start receiving data
        if connectionStatus == .buffering {
            DispatchQueue.main.async {
                self.connectionStatus = .connected
            }
        }
        
        // Detect content type based on URL or initial data
        if let url = dataTask.originalRequest?.url,
           url.path.contains("yuv420") {
            // Handle YUV420 streaming
            print("📡 Processing as YUV420 stream")
            yuvBuffer.append(data)
            processAccumulatedYUV420Data()
        } else {
            // Default to YUV420 processing
            print("📡 Processing as YUV420 stream (default)")
            yuvBuffer.append(data)
            processAccumulatedYUV420Data()
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("📡 Received response: \(response)")
        DispatchQueue.main.async {
            self.connectionStatus = .connected
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard isStreaming else { return }
        
        DispatchQueue.main.async {
            if let error = error {
                self.connectionStatus = .error(error.localizedDescription)
            } else {
                self.connectionStatus = .disconnected
            }
            self.isStreaming = false
        }
    }
    private func processAccumulatedYUV420Data() {
        // Early exit if streaming has been stopped
        guard isStreaming && connectionStatus != .disconnected else {
            print("📡 Skipping YUV420 processing - streaming stopped")
            yuvBuffer.removeAll() // Clear buffer if stopped
            return
        }
        
        print("📡 Processing YUV420 buffer with \(yuvBuffer.count) bytes")
        
        // If we don't have a frame header yet, try to parse one
        if frameHeader == nil && yuvBuffer.count >= YUV420FrameHeader.headerSize {
            let headerData = yuvBuffer.subdata(in: 0..<YUV420FrameHeader.headerSize)
            
            // Debug: Print raw header bytes
            let hexString = headerData.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("📡 Raw header bytes: \(hexString)")
            
            // Debug: Parse each UInt32 individually to see what we get
            let width = headerData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
            let height = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).bigEndian }
            let ySize = headerData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).bigEndian }
            let uSize = headerData.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self).bigEndian }
            let vSize = headerData.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self).bigEndian }
            
            print("📡 Raw parsed values: width=\(width), height=\(height), ySize=\(ySize), uSize=\(uSize), vSize=\(vSize)")
            
            frameHeader = YUV420FrameHeader(from: headerData)
            
            if let header = frameHeader {
                expectedFrameSize = Int(header.totalSize) + YUV420FrameHeader.headerSize
                print("📡 Parsed YUV420 header: \(header.width)x\(header.height), Y:\(header.ySize) U:\(header.uSize) V:\(header.vSize), total size: \(expectedFrameSize)")
            } else {
                print("📡 Failed to parse YUV420 header")
            }
        }
        
        // If we have a complete frame, process it
        if let header = frameHeader, yuvBuffer.count >= expectedFrameSize {
            let frameData = yuvBuffer.subdata(in: YUV420FrameHeader.headerSize..<expectedFrameSize)
            yuvBuffer.removeSubrange(0..<expectedFrameSize)
            
            print("📡 Processing YUV420 frame with \(frameData.count) bytes")
            
            // Process the YUV420 frame
            DispatchQueue.main.async {
                if let image = self.createImageFromYUV420Data(frameData, header: header) {
                    print("📡 Successfully created image from YUV420 data")
                    self.addFrameToBuffer(image)
                    if self.connectionStatus != .streaming {
                        self.connectionStatus = .streaming
                        self.startFramePlayback()
                    }
                } else {
                    print("📡 Failed to create image from YUV420 data")
                }
            }
            
            // Reset for next frame
            frameHeader = nil
            expectedFrameSize = 0
        }
    }
    
    private func createImageFromYUV420Data(_ data: Data, header: YUV420FrameHeader) -> UIImage? {
        let width = Int(header.width)
        let height = Int(header.height)
        let ySize = Int(header.ySize)
        let uSize = Int(header.uSize)
        let vSize = Int(header.vSize)
        
        guard data.count >= ySize + uSize + vSize else {
            print("📡 Insufficient YUV420 data")
            return nil
        }
        
        // Extract Y, U, V planes
        let yData = data.subdata(in: 0..<ySize)
        let uData = data.subdata(in: ySize..<(ySize + uSize))
        let vData = data.subdata(in: (ySize + uSize)..<(ySize + uSize + vSize))
        
        // Create CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8Planar,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("📡 Failed to create CVPixelBuffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        // Copy Y plane
        if let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            yData.withUnsafeBytes { yBytes in
                for row in 0..<height {
                    let srcOffset = row * width
                    let dstOffset = row * yBytesPerRow
                    memcpy(yBaseAddress + dstOffset, yBytes.baseAddress! + srcOffset, width)
                }
            }
        }
        
        // Copy U plane
        if let uBaseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let uBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let uWidth = width / 2
            let uHeight = height / 2
            uData.withUnsafeBytes { uBytes in
                for row in 0..<uHeight {
                    let srcOffset = row * uWidth
                    let dstOffset = row * uBytesPerRow
                    memcpy(uBaseAddress + dstOffset, uBytes.baseAddress! + srcOffset, uWidth)
                }
            }
        }
        
        // Copy V plane
        if let vBaseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, 2) {
            let vBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 2)
            let vWidth = width / 2
            let vHeight = height / 2
            vData.withUnsafeBytes { vBytes in
                for row in 0..<vHeight {
                    let srcOffset = row * vWidth
                    let dstOffset = row * vBytesPerRow
                    memcpy(vBaseAddress + dstOffset, vBytes.baseAddress! + srcOffset, vWidth)
                }
            }
        }
        
        // Convert CVPixelBuffer to CGImage
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage)
        
        guard let finalImage = cgImage else {
            print("📡 Failed to create CGImage from CVPixelBuffer")
            return nil
        }
        
        return UIImage(cgImage: finalImage)
    }
    
    private func startFramePlayback() {
        // Don't start frame playback timer if we're using Android polling
        // (Android polling handles frame display directly)
        if let url = dataTask?.originalRequest?.url,
           url.path.contains("/api/android/frame") {
            print("📡 🚫 Skipping frame playback timer - using Android polling")
            return
        }
        
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            self.displayNextFrame()
        }
    }
    
    private func addFrameToBuffer(_ image: UIImage) {
        guard isStreaming else {
            print("📡 🚫 Ignoring frame - streaming stopped")
            return
        }
        
        print("📡 🎞️ Displaying frame directly! Image size: \(image.size)")
        
        // For Android polling, display frames immediately without buffering
        DispatchQueue.main.async {
            self.currentFrame = image
            print("📡 🖼️ Frame set as currentFrame! Should be visible now.")
        }
        
        // Update frame rate calculation
        calculateFrameRate()
    }
    
    private func displayNextFrame() {
        guard isStreaming, !frameBuffer.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStreaming, !self.frameBuffer.isEmpty else { return }
            self.currentFrame = self.frameBuffer.removeFirst()
        }
    }
    
    private func calculateFrameRate() {
        frameCount += 1
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastFrameTime)
        
        if timeDiff >= 1.0 {
            frameRate = Double(frameCount) / timeDiff
            frameCount = 0
            lastFrameTime = now
        }
    }
    
    private func decodeH264ToImage(_ h264Data: Data, width: Int, height: Int) -> UIImage? {
        // Create CMSampleBuffer from H.264 data
        guard let sampleBuffer = createSampleBuffer(from: h264Data) else {
            print("📡 Failed to create CMSampleBuffer from H.264 data")
            return nil
        }
        
        // Get format description from sample buffer
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("📡 Failed to get format description from sample buffer")
            return nil
        }
        
        // Create VTDecompressionSession
        var decompressionSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height
            ] as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &decompressionSession
        )
        
        guard status == noErr, let session = decompressionSession else {
            print("📡 Failed to create VTDecompressionSession: \(status)")
            return nil
        }
        
        // Decode frame
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
        
        VTDecompressionSessionInvalidate(session)
        
        guard decodeStatus == noErr else {
            print("📡 Failed to decode H.264 frame: \(decodeStatus)")
            return nil
        }
        
        // For now, create a placeholder image since VideoToolbox decoding is complex
        // In a real implementation, you'd need to properly handle the asynchronous nature
        return createPlaceholderImage(width: width, height: height)
    }
    
    private func createSampleBuffer(from h264Data: Data) -> CMSampleBuffer? {
        // Simplified implementation - creates a placeholder
        // Real implementation would need proper H.264 parsing and CMSampleBuffer creation
        return nil
    }
    
    private func createPlaceholderImage(width: Int, height: Int) -> UIImage? {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Create a gradient background to indicate H.264 frame received
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )
            
            context.cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint.zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // Add H.264 indicator text
            let text = "H.264 Frame\n\(width)×\(height)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: CGFloat(min(width, height)) / 20.0, weight: .bold),
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attrs)
        }
    }
    
    deinit {
        print("📡 FrameStreamManager deinit - ensuring cleanup")
        
        // Stop all operations immediately
        isStreaming = false
        
        // Clear current frame immediately (no async needed in deinit)
        currentFrame = nil
        
        // Cancel timers and delayed operations first
        frameTimer?.invalidate()
        frameTimer = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        
        // Clean up URLSession and network tasks
        cleanupURLSession()
        
        // Clear all buffers and state
        yuvBuffer.removeAll()
        frameHeader = nil
        expectedFrameSize = 0
        frameBuffer.removeAll()
        
        print("📡 FrameStreamManager deinitialized")
    }
}

struct TeleVisionView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var navigationManager: NavigationManager
    @StateObject private var streamManager = FrameStreamManager()
    @StateObject private var intelligenceChecker = AppleIntelligenceChecker()
    @StateObject private var helpManager = WebSocketHelpManager()
    
    @State private var isOn = false
    @State private var isFullScreen = false
    @State private var isPiPMode = false
    @State private var scale: CGFloat = 1.0
    @State private var streamURL = "https://magictrafficlight-production-b5ed.up.railway.app/api/android/frame/latest"
    @State private var showStreamSettings = false
    @State private var isLoading = false
    @State private var loadingTimer: Timer?
    @State private var isRequestSuccessful = false
    @State private var isStopping = false
    @State private var isShining = false
    
    // New states for realistic help request flow
    @State private var isRequestSent = false
    @State private var isAwaitingAcceptance = false
    @State private var isRequestTimeout = false
    @State private var isRequestRejected = false
    @State private var requestSentTimer: Timer?
    @State private var awaitingTimer: Timer?
    @State private var feedbackTimer: Timer?
    @State private var locationStreamingTimer: Timer?
    
    // 16:9 aspect ratio dimensions
    private var tvWidth: CGFloat {
        if isFullScreen {
            return UIScreen.main.bounds.width
        } else if isPiPMode {
            return 300
        } else {
            return 120
        }
    }
    
    private var tvHeight: CGFloat {
        if isFullScreen {
            return UIScreen.main.bounds.height
        } else if isPiPMode {
            return 168.75
        } else {
            return 67.5
        }
    }
    
    // MARK: - Computed Properties for Request Button
    private var buttonText: String {
        if isStopping {
            return "Stopping.."
        } else if isRequestSuccessful {
            return "Streaming Location"
        } else if isRequestTimeout {
            return "Timeout"
        } else if isRequestRejected {
            return "Rejected"
        } else if isAwaitingAcceptance {
            return "Awaiting acceptance..."
        } else if isRequestSent {
            return "Help Request sent"
        } else {
            return "Request"
        }
    }
    
    private var buttonBackgroundColor: Color {
        if isStopping {
            return Color.red
        } else if isRequestSuccessful {
            return Color.green
        } else if isAwaitingAcceptance {
            return Color.orange
        } else if isRequestSent {
            return Color.yellow
        } else if isLoading {
            return Color.orange
        } else if !helpManager.isConnected {
            return Color.gray
        } else {
            return Color.blue
        }
    }
    
    var body: some View {
        ZStack {
            // Normal/PiP mode view
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    // Request Button
                    Button(action: handleRequest) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else if isStopping {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else if isRequestSuccessful {
                                Image(systemName: "location.fill")
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(buttonText)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(buttonBackgroundColor)
                        .cornerRadius(8)
                    }
                    .disabled(!helpManager.isConnected || isLoading || isStopping)
                    
                    // TV Frame
                    tvFrameView
                }
                .frame(width: max(tvWidth, 160)) // Fixed VStack width based on TV or minimum button width
            }
            .opacity(isFullScreen ? 0 : 1)
        }
        .overlay(
            Group {
                if isFullScreen {
                    fullScreenTVView
                }
            }
        )
        .onChange(of: isFullScreen) { _, newValue in
            // Notify parent view about fullscreen state change
            NotificationCenter.default.post(
                name: NSNotification.Name("TeleVisionFullScreenChanged"),
                object: nil,
                userInfo: ["isFullScreen": newValue]
            )
        }
        .onAppear {
            print("📱 🚀 TeleVisionView: onAppear called")
            print("📱 📡 Current streamURL: \(streamURL)")
            
            // Set HTTP polling URL for iOS client to receive Android RGBA frames from Railway
            streamURL = "https://magictrafficlight-production-b5ed.up.railway.app/api/android/frame/latest"
            print("📱 🔗 Updated streamURL to Android frame polling endpoint: \(streamURL)")
            
            // Auto turn on when navigation starts and auto-connect to stream
            if navigationManager.isNavigating && !isOn {
                print("📱 🗺️ Navigation is active, turning on TV")
                withAnimation(.easeInOut(duration: 0.5)) {
                    isOn = true
                }
            }
            
            // Auto-connect to YUV stream endpoint when TV is on
            if isOn {
                print("📱 📺 TV is on, auto-connecting to stream")
                connectToStream()
            } else {
                print("📱 📺 TV is off, not auto-connecting")
            }
            
            // Automatically attempt WebSocket connection for help requests
            print("🔗 TeleVisionView: Auto-connecting to WebSocket for help requests")
            helpManager.connect()
            
            // Set up help response callback
            helpManager.onHelpResponse = { [self] response in
                DispatchQueue.main.async {
                    switch response {
                    case "accepted":
                        // Cancel the awaiting timer since we got an early response
                        awaitingTimer?.invalidate()
                        // Transition to streaming state
                        isAwaitingAcceptance = false
                        isRequestSuccessful = true
                        print("✅ Help request accepted - cancelling timeout and transitioning to success state")
                        
                        // Start streaming location to helper
                        startLocationStreaming()
                    case "rejected":
                        // Cancel timers and show rejected state
                        awaitingTimer?.invalidate()
                        requestSentTimer?.invalidate()
                        isAwaitingAcceptance = false
                        isRequestRejected = true
                        print("❌ Help request rejected - Showing rejection message")
                        
                        // Show "Rejected" for 2 seconds before resetting
                        feedbackTimer?.invalidate()
                        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                            DispatchQueue.main.async {
                                isRequestRejected = false
                                isRequestSent = false
                                print("🔄 Reset to initial state after rejection")
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }
        .onChange(of: navigationManager.isNavigating) { _, isNavigating in
            if isNavigating && !isOn {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isOn = true
                }
            }
        }
        .onChange(of: isOn) { _, newValue in
            if !newValue {
                // Disconnect when TV is turned off
                streamManager.stopStreaming()
            }
        }
        .sheet(isPresented: $showStreamSettings) {
            streamSettingsView
        }
        .onDisappear {
            streamManager.stopStreaming()
            helpManager.disconnect()
            stopLocationStreaming()
        }
    }
    
    private var streamSettingsView: some View {
        NavigationView {
            Form {
                Section("Stream Configuration") {
                    TextField("Stream URL", text: $streamURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    HStack {
                        Text("Status:")
                        Spacer()
                        switch streamManager.connectionStatus {
                        case .disconnected:
                            Text("Disconnected").foregroundColor(.red)
                        case .connecting:
                            Text("Connecting...").foregroundColor(.orange)
                        case .connected:
                            Text("Connected").foregroundColor(.green)
                        case .streaming:
                            Text("Streaming").foregroundColor(.blue)
                        case .error(let message):
                            Text("Error: \(message)").foregroundColor(.red)
                        default:
                            Text("Unknown").foregroundColor(.gray)
                        }
                    }
                    
                    if streamManager.frameRate > 0 {
                        HStack {
                            Text("Frame Rate:")
                            Spacer()
                            Text("\(Int(streamManager.frameRate)) fps")
                        }
                    }
                }
                
                Section("Railway Android Frame Polling (Recommended)") {
                    Button("Android RGBA Frames (Live)") {
                        streamURL = "https://magictrafficlight-production-b5ed.up.railway.app/api/android/frame/latest"
                    }
                    .foregroundColor(.green)
                    
                    Button("Local Android Frames") {
                        streamURL = "http://127.0.0.1:8080/api/android/frame/latest"
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Railway H.264 Streaming (Legacy)") {
                    Button("H.264 WebSocket Stream") {
                        streamURL = "wss://magictrafficlight-production-b5ed.up.railway.app/ws/h264/client"
                    }
                    .foregroundColor(.orange)
                    
                    Button("Local H.264 Stream") {
                        streamURL = "ws://127.0.0.1:8080/ws/h264/client"
                    }
                    .foregroundColor(.orange)
                }
                
                Section("Railway YUV420 Streaming (Legacy)") {
                    Button("YUV420 Sample (MOV Processing)") {
                        streamURL = "https://magictrafficlight-production-b5ed.up.railway.app/yuv420/sample"
                    }
                    .foregroundColor(.purple)
                    
                    Button("YUV420 Generated Frames") {
                        streamURL = "https://magictrafficlight-production-b5ed.up.railway.app/yuv420/stream"
                    }
                    .foregroundColor(.cyan)
                }
                
                Section("Local Development") {
                    Button("Local YUV420 Sample") {
                        streamURL = "http://127.0.0.1:8080/yuv420/sample"
                    }
                    .foregroundColor(.orange)
                    
                    Button("Local YUV420 Stream") {
                        streamURL = "http://127.0.0.1:8080/yuv420/stream"
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Actions") {
                    Button(streamManager.isStreaming ? "Disconnect" : "Connect") {
                        if streamManager.isStreaming {
                            streamManager.stopStreaming()
                        } else {
                            connectToStream()
                        }
                    }
                    .disabled(streamURL.isEmpty)
                    
                    Button("Test Connection") {
                        // Quick connection test
                        guard let url = URL(string: streamURL) else { return }
                        
                        URLSession.shared.dataTask(with: url) { data, response, error in
                            DispatchQueue.main.async {
                                if error != nil {
                                    // Show error alert
                                } else {
                                    // Show success
                                }
                            }
                        }.resume()
                    }
                    .disabled(streamURL.isEmpty)
                }
            }
            .navigationTitle("Stream Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showStreamSettings = false
                    }
                }
            }
        }
    }
    
    private var tvFrameView: some View {
        ZStack {
            // TV Frame
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: tvWidth, height: tvHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2)
            
            // Screen Content
            if isOn {
                screenContent
                    .frame(width: tvWidth - 8, height: tvHeight - 8)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // Off screen - dark with subtle reflection
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black,
                                Color.gray.opacity(0.1),
                                Color.black
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: tvWidth - 8, height: tvHeight - 8)
            }
            
            // Power indicator LED
            Circle()
                .fill(isOn ? Color.green : Color.red.opacity(0.6))
                .frame(width: 4, height: 4)
                .offset(x: tvWidth/2 - 8, y: tvHeight/2 - 8)
                .opacity(0.8)
        }
        .scaleEffect(scale)
        .overlay(
            // Apple Intelligence Shine Effect (only in minified mode)
            Group {
                if !isFullScreen {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(isShining ? 0.8 : 0),
                                    Color.purple.opacity(isShining ? 0.6 : 0),
                                    Color.pink.opacity(isShining ? 0.8 : 0),
                                    Color.blue.opacity(isShining ? 0.8 : 0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isShining ? 3 : 0
                        )
                        .frame(width: tvWidth + 6, height: tvHeight + 6)
                        .scaleEffect(isShining ? 1.05 : 1.0)
                        .opacity(isShining ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true), value: isShining)
                }
            }
        )
        .onTapGesture(count: 2) {
            // Double tap to cycle through sizes: small -> PiP -> fullscreen -> small
            handleDoubleTap()
        }
        .onChange(of: intelligenceChecker.isAvailable) { _, isAvailable in
            if isAvailable && !isShining {
                // Trigger shine effect when Apple Intelligence is detected
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        isShining = true
                    }
                    
                    // Stop shining after the animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            isShining = false
                        }
                    }
                }
            }
        }
    }
    
    private var fullScreenTVView: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            // Screen Content - fullscreen
            if isOn {
                if streamManager.isStreaming, let frame = streamManager.currentFrame {
                    // Live stream in fullscreen
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                        .overlay(
                            VStack {
                                Spacer()
                                HStack {
                                    Circle()
                                        .fill(statusColor)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(statusText)
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if streamManager.frameRate > 0 {
                                        Text("\(Int(streamManager.frameRate)) fps")
                                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(12)
                            }
                        )
                } else {
                    // No signal placeholder in fullscreen
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .foregroundColor(.gray)
                            .font(.system(size: 60))
                        
                        Text("NO SIGNAL")
                            .font(.system(size: 24, weight: .regular, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            } else {
                // Off screen
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black,
                                Color.gray.opacity(0.1),
                                Color.black
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .ignoresSafeArea()
            }
            
            // Exit fullscreen button
            VStack {
                HStack {
                    // Apple Intelligence indicator in fullscreen
                    if intelligenceChecker.isAvailable {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text("AI Enhanced")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.leading)
                    }
                    
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isFullScreen = false
                            isPiPMode = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onTapGesture(count: 2) {
            // Double tap to exit fullscreen
            handleDoubleTap()
        }
    }
    
    @ViewBuilder
    private var screenContent: some View {
        // Live stream view
        if streamManager.isStreaming, let frame = streamManager.currentFrame {
            streamView(frame: frame)
        } else if streamManager.connectionStatus == .connected || streamManager.connectionStatus == .streaming {
            // Connected but no frames yet - show waiting message for Android polling
            if streamURL.contains("/api/android/frame") {
                // Android polling mode - show polling indicator
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack {
                            Text("POLLING")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Waiting for Android frames...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    )
            } else {
                // Other modes - show black screen
                Rectangle()
                    .fill(Color.black)
            }
        } else {
            // Not connected - show NO SIGNAL
            streamPlaceholder
        }
    }
    
    private func streamView(frame: UIImage) -> some View {
        ZStack {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: isFullScreen ? UIScreen.main.bounds.width : (tvWidth - 8), 
                       height: isFullScreen ? UIScreen.main.bounds.height : (tvHeight - 8))
                .clipped()
            
            // Stream status overlay
            VStack {
                Spacer()
                HStack {
                    // Connection status indicator
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    
                    Text(statusText)
                        .font(.system(size: isFullScreen ? 12 : 8, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Frame rate indicator
                    if streamManager.frameRate > 0 {
                        Text("\(Int(streamManager.frameRate)) fps")
                            .font(.system(size: isFullScreen ? 12 : 8, weight: .regular, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(isFullScreen ? 4 : 2)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(isFullScreen ? 8 : 4)
            }
        }
        .onLongPressGesture {
            showStreamSettings = true
        }
    }
    
    private var streamPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
            
            VStack(spacing: 4) {
                Image(systemName: "video.slash")
                    .foregroundColor(.gray)
                    .font(.system(size: isFullScreen ? 24 : 12))
                
                Text("NO SIGNAL")
                    .font(.system(size: isFullScreen ? 10 : 6, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text("Tap to connect")
                    .font(.system(size: isFullScreen ? 8 : 4, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
        .onTapGesture {
            connectToStream()
        }
        .onLongPressGesture {
            showStreamSettings = true
        }
    }
    
    private var statusColor: Color {
        switch streamManager.connectionStatus {
        case .connected, .streaming:
            return .green
        case .connecting, .buffering:
            return .yellow
        case .disconnected:
            return .red
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch streamManager.connectionStatus {
        case .connected:
            return "CONNECTED"
        case .connecting:
            return "CONNECTING"
        case .streaming:
            return "LIVE"
        case .buffering:
            return "BUFFERING"
        case .disconnected:
            return "OFFLINE"
        case .error(_):
            return "ERROR"
        }
    }
    
    private var staticNoise: some View {
        ZStack {
            // Background static
            Rectangle()
                .fill(Color.black)
            
            // Simple static noise pattern
            ForEach(0..<50, id: \.self) { _ in
                Rectangle()
                    .fill(Color.white.opacity(Double.random(in: 0.1...0.8)))
                    .frame(
                        width: Double.random(in: 1...3),
                        height: Double.random(in: 1...3)
                    )
                    .position(
                        x: Double.random(in: 0...(tvWidth - 8)),
                        y: Double.random(in: 0...(tvHeight - 8))
                    )
            }
        }
    }
    
    private func connectToStream() {
        guard !streamURL.isEmpty, let url = URL(string: streamURL) else { 
            print("🔴 TeleVision: Invalid stream URL: '\(streamURL)'")
            return 
        }
        
        print("🔗 TeleVision: Connecting to stream: \(streamURL)")
        print("🔗 🔍 URL components:")
        print("🔗   - Scheme: \(url.scheme ?? "nil")")
        print("🔗   - Host: \(url.host ?? "nil")")
        print("🔗   - Port: \(url.port?.description ?? "default")")
        print("🔗   - Path: \(url.path)")
        print("🔗   - Query: \(url.query ?? "nil")")
        
        // Check if it's a WebSocket URL
        if streamURL.lowercased().contains("ws://") || streamURL.lowercased().contains("wss://") {
            print("🔗 🎯 Detected WebSocket URL - this should trigger H.264 processing")
        } else if streamURL.lowercased().contains("/api/android/frame") {
            print("🔗 🎯 Detected Android polling URL - this should trigger RGBA polling")
        } else {
            print("🔗 ⚠️ Non-WebSocket URL detected")
        }
        
        streamManager.startStreaming(from: url)
    }
    
    private func startDemoStream() {
        // Create demo traffic camera stream with sample images
        streamManager.isStreaming = true
        streamManager.connectionStatus = .connected
        
        // Create a timer to simulate frames
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            // Create sample traffic scene images
            let demoImages = createDemoTrafficImages()
            let randomImage = demoImages.randomElement() ?? createDefaultTrafficImage()
            
            DispatchQueue.main.async {
                self.streamManager.currentFrame = randomImage
                self.streamManager.frameRate = 2.0 // 2 FPS demo
            }
            
            // Stop after some time or when disconnected
            if !self.streamManager.isStreaming {
                timer.invalidate()
            }
        }
    }
    
    private func createDemoTrafficImages() -> [UIImage] {
        var images: [UIImage] = []
        
        // Create sample traffic scenes
        for i in 1...4 {
            let image = createTrafficSceneImage(scene: i)
            images.append(image)
        }
        
        return images
    }
    
    private func createTrafficSceneImage(scene: Int) -> UIImage {
        let size = CGSize(width: 640, height: 360) // 16:9 aspect ratio
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Background (road)
            UIColor.darkGray.setFill()
            context.fill(rect)
            
            drawRoadMarkings(context: context, size: size)
            drawCars(context: context, size: size, scene: scene)
            drawTrafficLight(context: context, size: size, scene: scene)
            drawTextOverlays(context: context, size: size, scene: scene)
        }
    }
    
    private func drawRoadMarkings(context: UIGraphicsImageRendererContext, size: CGSize) {
        // Road markings
        UIColor.yellow.setStroke()
        context.cgContext.setLineWidth(4)
        context.cgContext.setLineDash(phase: 0, lengths: [20, 10])
        
        let centerY = size.height / 2
        context.cgContext.move(to: CGPoint(x: 0, y: centerY))
        context.cgContext.addLine(to: CGPoint(x: size.width, y: centerY))
        context.cgContext.strokePath()
    }
    
    private func drawCars(context: UIGraphicsImageRendererContext, size: CGSize, scene: Int) {
        // Cars (rectangles representing vehicles)
        let carColors: [UIColor] = [.red, .blue, .white, .black, .systemGreen]
        let centerY = size.height / 2
        
        for i in 0..<(2 + scene) {
            let color = carColors[i % carColors.count]
            color.setFill()
            
            let carWidth: CGFloat = 60
            let carHeight: CGFloat = 30
            let x = CGFloat(50 + i * 120 + scene * 20) // Offset based on scene
            let y = centerY - carHeight/2 + (i % 2 == 0 ? -40 : 40) // Alternate lanes
            
            let carRect = CGRect(x: x, y: y, width: carWidth, height: carHeight)
            context.fill(carRect)
            
            // Car outline
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(2)
            context.stroke(carRect)
        }
    }
    
    private func drawTrafficLight(context: UIGraphicsImageRendererContext, size: CGSize, scene: Int) {
        // Traffic light (if visible)
        if scene % 2 == 0 {
            // Traffic light pole
            UIColor.gray.setFill()
            let poleRect = CGRect(x: size.width - 60, y: 50, width: 8, height: 100)
            context.fill(poleRect)
            
            // Traffic light box
            UIColor.black.setFill()
            let lightBox = CGRect(x: size.width - 85, y: 50, width: 40, height: 80)
            context.fill(lightBox)
            
            drawTrafficLights(context: context, size: size, scene: scene)
        }
    }
    
    private func drawTrafficLights(context: UIGraphicsImageRendererContext, size: CGSize, scene: Int) {
        // Lights
        let lightSize: CGFloat = 15
        let lights = [
            (color: scene == 2 ? UIColor.red : UIColor.darkGray, y: 55),
            (color: scene == 4 ? UIColor.yellow : UIColor.darkGray, y: 75),
            (color: scene == 1 ? UIColor.green : UIColor.darkGray, y: 95)
        ]
        
        for light in lights {
            light.color.setFill()
            let lightRect = CGRect(
                x: size.width - 82.5,
                y: CGFloat(light.y),
                width: lightSize,
                height: lightSize
            )
            context.cgContext.fillEllipse(in: lightRect)
        }
    }
    
    private func drawTextOverlays(context: UIGraphicsImageRendererContext, size: CGSize, scene: Int) {
        // Timestamp overlay
        let timestamp = "Traffic Cam - Demo Feed"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .strokeColor: UIColor.black,
            .strokeWidth: -2
        ]
        
        timestamp.draw(at: CGPoint(x: 10, y: 10), withAttributes: attrs)
        
        // Scene number
        let sceneText = "Scene \(scene)"
        sceneText.draw(at: CGPoint(x: 10, y: size.height - 30), withAttributes: attrs)
    }
    
    private func createDefaultTrafficImage() -> UIImage {
        return createTrafficSceneImage(scene: 1)
    }
    
    private func handlePictureInPictureSwap() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isFullScreen.toggle()
            
            // Add haptic feedback for the swap
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        
        // Optional: Notify other parts of the app about the swap
        // This could be used to temporarily disable map interactions in minified mode
        NotificationCenter.default.post(
            name: NSNotification.Name("TeleVisionSwapped"),
            object: nil,
            userInfo: ["isFullScreen": isFullScreen]
        )
    }
    
    private func handleDoubleTap() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            if !isPiPMode && !isFullScreen {
                // Small -> PiP
                isPiPMode = true
            } else if isPiPMode && !isFullScreen {
                // PiP -> Full screen
                isPiPMode = false
                isFullScreen = true
            } else {
                // Full screen -> Small
                isFullScreen = false
                isPiPMode = false
            }
            
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        
        // Notify about the state change
        NotificationCenter.default.post(
            name: NSNotification.Name("TeleVisionSwapped"),
            object: nil,
            userInfo: [
                "isPiPMode": isPiPMode,
                "isFullScreen": isFullScreen
            ]
        )
    }
    
    private func handleRequest() {
        if isRequestSuccessful {
            handleStop()
            return
        }
        
        guard !isLoading else { return }
        guard helpManager.isConnected else {
            print("🔴 Cannot send help request - WebSocket not connected")
            return
        }
        
        isLoading = true
        print("📱 Sending help request via WebSocket...")
        
        // Send help request with current location
        let currentLocation = locationManager.location
        helpManager.sendHelpRequest(location: currentLocation, navigationManager: navigationManager)
        
        // Step 1: Show "Help Request sent" briefly (2 seconds)
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isRequestSent = true
                print("✅ Help request sent successfully via WebSocket")
                
                // Step 2: Show "Awaiting acceptance..." (2 seconds after first message)
                self.requestSentTimer?.invalidate()
                self.requestSentTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        self.isRequestSent = false
                        self.isAwaitingAcceptance = true
                        print("⏳ Awaiting help request acceptance...")
                        
                        // Step 3: Reset to initial state after 10 seconds if no response
                        self.awaitingTimer?.invalidate()
                        self.awaitingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                            DispatchQueue.main.async {
                                // Check if the request hasn't already been accepted or rejected
                                guard self.isAwaitingAcceptance && !self.isRequestSuccessful && !self.isRequestRejected else {
                                    print("🔄 Timer fired but request already handled - ignoring timeout")
                                    return
                                }
                                
                                self.isAwaitingAcceptance = false
                                self.isRequestTimeout = true
                                print("⏰ No response received - Showing timeout message")
                                
                                // Show "Timeout" for 2 seconds before resetting
                                self.feedbackTimer?.invalidate()
                                self.feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                                    DispatchQueue.main.async {
                                        self.isRequestTimeout = false
                                        self.isRequestSent = false
                                        self.isRequestSuccessful = false
                                        print("🔄 Reset to initial state after timeout")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startLocationStreaming() {
        // Stop any existing streaming timer
        locationStreamingTimer?.invalidate()
        
        print("📍 Starting location streaming to helper")
        
        // Send initial location immediately
        Task { @MainActor in
            if let location = locationManager.location {
                helpManager.sendLocationUpdate(location: location)
            }
        }
        
        // Set up periodic location updates every 3 seconds
        locationStreamingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard self.isRequestSuccessful else {
                // Stop streaming if no longer in success state
                self.stopLocationStreaming()
                return
            }
            
            Task { @MainActor in
                if let location = self.locationManager.location {
                    self.helpManager.sendLocationUpdate(location: location)
                }
            }
        }
    }
    
    private func stopLocationStreaming() {
        locationStreamingTimer?.invalidate()
        locationStreamingTimer = nil
        print("📍 Stopped location streaming")
    }
    
    private func handleStop() {
        guard !isStopping else { return }
        
        isStopping = true
        print("Stopping stream...")
        
        // Clean up all timers
        loadingTimer?.invalidate()
        requestSentTimer?.invalidate()
        awaitingTimer?.invalidate()
        feedbackTimer?.invalidate()
        locationStreamingTimer?.invalidate()
        
        // Stop location streaming
        stopLocationStreaming()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isStopping = false
            self.isRequestSuccessful = false
            self.isRequestSent = false
            self.isAwaitingAcceptance = false
            self.isRequestTimeout = false
            self.isRequestRejected = false
            print("Stream stopped - Ready for new request")
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Preview placeholder - replace with actual managers in real usage
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 120, height: 67.5)
                    .cornerRadius(8)
                    .overlay(
                        Text("TeleVision")
                            .foregroundColor(.green)
                            .font(.caption2)
                    )
                    .padding()
            }
        }
    }
}
