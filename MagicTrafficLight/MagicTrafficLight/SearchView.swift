//
//  SearchView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI
import MapKit
import Speech
import AVFoundation
import UIKit

struct SearchView: View {
    @ObservedObject var navigationManager: NavigationManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showingHistory = false
    let onDismiss: () -> Void
    
    // Voice Search Properties
    @State private var isListening = false
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var showingVoicePermissionAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar at the top
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                
                Divider()
            }
            
            // Content Area
            ScrollView {
                VStack(spacing: 0) {
                    if !searchText.isEmpty && (isSearchFocused || !navigationManager.searchResults.isEmpty) {
                        searchResults
                    } else {
                        searchHistory
                    }
                }
            }
            .background(.ultraThinMaterial)
        }
        .cornerRadius(12)
        .shadow(radius: 2)
        .onAppear {
            isSearchFocused = true
            showingHistory = true
            
            // Check speech authorization status
            speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        }
        .onDisappear {
            // Stop voice search when view disappears
            if isListening {
                stopListening()
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search destination...", text: $searchText)
                .focused($isSearchFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16))
                .onSubmit {
                    if !searchText.isEmpty {
                        navigationManager.searchForPlaces(query: searchText)
                    }
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        navigationManager.searchResults = []
                    } else {
                        navigationManager.searchForPlaces(query: newValue)
                    }
                }
            
            // Voice Search Button
            Button(action: {
                if isListening {
                    stopListening()
                } else {
                    startVoiceSearch()
                }
            }) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .foregroundColor(isListening ? .red : (speechAuthorizationStatus == .authorized ? .blue : .gray))
                    .font(.system(size: 16, weight: .medium))
                    .scaleEffect(isListening ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isListening)
            }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    navigationManager.searchResults = []
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .alert("Voice Search Permission", isPresented: $showingVoicePermissionAlert) {
            Button("Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable Speech Recognition in Settings to use voice search.")
        }
    }
    
    private var searchResults: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if navigationManager.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if navigationManager.searchResults.isEmpty && !searchText.isEmpty {
                Text("No results found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(navigationManager.searchResults, id: \.self) { result in
                    SearchResultRow(mapItem: result) {
                        navigationManager.selectDestination(result)
                        searchText = ""
                        isSearchFocused = false
                        dismissWithCleanup() // Auto-close the dialog with voice cleanup
                    }
                }
            }
        }
    }
    
    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Searches")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !navigationManager.searchHistory.isEmpty {
                    Button("Clear") {
                        navigationManager.clearSearchHistory()
                        showingHistory = false
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            if navigationManager.searchHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text("No recent searches")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text("Start searching for destinations to see your history here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(navigationManager.searchHistory) { item in
                            SearchHistoryRow(item: item) {
                                navigationManager.selectFromHistory(item)
                                showingHistory = false
                                dismissWithCleanup() // Auto-close the dialog with voice cleanup
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    // MARK: - Voice Search Methods
    
    private func startVoiceSearch() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            showingVoicePermissionAlert = true
            return
        }
        
        requestSpeechPermission { [self] authorized in
            DispatchQueue.main.async {
                if authorized {
                    self.startRecording()
                } else {
                    self.showingVoicePermissionAlert = true
                }
            }
        }
    }
    
    private func stopListening() {
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Update state
        isListening = false
        
        // Deactivate audio session
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        #endif
    }
    
    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.speechAuthorizationStatus = .authorized
                    completion(true)
                case .denied, .restricted, .notDetermined:
                    self.speechAuthorizationStatus = authStatus
                    completion(false)
                @unknown default:
                    self.speechAuthorizationStatus = .notDetermined
                    completion(false)
                }
            }
        }
    }
    
    private func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        #endif
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        
        guard let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer else {
            print("Unable to create speech recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                DispatchQueue.main.async {
                    self.searchText = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                DispatchQueue.main.async {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isListening = false
                    
                    if !self.searchText.isEmpty {
                        self.navigationManager.searchForPlaces(query: self.searchText)
                    }
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func openSettings() {
        #if os(iOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        #endif
    }
    
    private func dismissWithCleanup() {
        // Stop voice search if active
        if isListening {
            stopListening()
        }
        // Call the original dismiss callback
        onDismiss()
    }
}

struct SearchResultRow: View {
    let mapItem: MKMapItem
    let onSelect: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mapItem.name ?? "Unknown Location")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if let address = mapItem.placemark.title {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(isPressed ? Color.gray.opacity(0.2) : Color.clear)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                performSelection()
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Divider()
                .padding(.leading, 12)
        }
    }
    
    private func performSelection() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Perform selection with slight delay to show visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onSelect()
        }
    }
}

struct SearchHistoryRow: View {
    let item: SearchHistoryItem
    let onSelect: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(item.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Text(timeAgoString(from: item.timestamp))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(isPressed ? Color.gray.opacity(0.2) : Color.clear)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                performSelection()
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Divider()
                .padding(.leading, 44)
        }
    }
    
    private func performSelection() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Perform selection with slight delay to show visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onSelect()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
