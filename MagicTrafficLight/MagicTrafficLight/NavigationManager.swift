//
//  NavigationManager.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import Foundation
import MapKit
import CoreLocation

@MainActor
class NavigationManager: NSObject, ObservableObject {
    static let shared = NavigationManager()
    
    // Navigation State
    @Published var isNavigating = false
    @Published var currentRoute: MKRoute?
    @Published var currentStep: MKRoute.Step?
    @Published var remainingDistance: CLLocationDistance = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var currentStepIndex = 0
    @Published var currentStepRemainingDistance: CLLocationDistance = 0
    
    // Search and History
    @Published var searchResults: [MKMapItem] = []
    @Published var searchHistory: [SearchHistoryItem] = []
    @Published var isSearching = false
    
    // Loading States
    @Published var isCalculatingRoute = false
    @Published var routeCalculationError: String?
    
    // Route Cancellation
    private var currentRouteTask: Task<Void, Never>?
    private var routeTimeoutTimer: Timer?
    
    // Destination
    @Published var destination: MKMapItem?
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    
    // Route Display
    @Published var routePolyline: MKPolyline?
    @Published var annotations: [MKPointAnnotation] = []
    @Published var userLocationAnnotation: MKPointAnnotation?
    @Published var shouldFocusOnStartingPoint = false
    @Published var shouldShowFullRoute = false
    @Published var shouldUpdateCamera = false // Trigger for camera following
    
    // LiveActivity Manager
    @Published var liveActivityManager = LiveActivityManager()
    
    // Auto-navigation properties
    @Published var isAutoNavigationEnabled = true
    private var proximityThreshold: CLLocationDistance = 50.0 // 50 meters before next instruction
    private var lastUserLocation: CLLocation?
    
    private let searchCompleter = MKLocalSearchCompleter()
    private var currentSearchTask: Task<Void, Never>?
    
    override init() {
        super.init()
        loadSearchHistory()
        setupSearchCompleter()
        setupLocationObserver()
        setupSiriNotificationObservers()
    }
    
    // MARK: - Location Monitoring for Auto-Navigation
    
    private func setupLocationObserver() {
        // Observe location changes from LocationManager
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LocationDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let location = notification.object as? CLLocation {
                Task { @MainActor in
                    self?.handleLocationUpdate(location)
                }
            }
        }
        
        // Observe heading changes from LocationManager for arrow rotation
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HeadingDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let heading = notification.object as? CLHeading {
                Task { @MainActor in
                    self?.handleHeadingUpdate(heading)
                }
            }
        }
    }
    
    // MARK: - Siri Notification Setup
    
    private func setupSiriNotificationObservers() {
        // Observe Siri navigation start request with fallback
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StartNavigationWithFallback"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStartNavigationWithFallback()
            }
        }
        
        // Observe Siri navigation stop request  
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StopActiveNavigation"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStopActiveNavigation()
            }
        }
    }
    
    private func handleStartNavigationWithFallback() {
        // Start navigation if there's a route preview ready, otherwise open search
        if currentRoute != nil && !isNavigating {
            startNavigation()
        } else {
            // Fallback to opening search dialog if no route exists
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenSearchDialog"),
                object: nil
            )
        }
    }
    
    private func handleStopActiveNavigation() {
        // Stop ongoing navigation if active
        if isNavigating {
            stopNavigation()
        }
    }
    
    private func handleLocationUpdate(_ location: CLLocation) {
        lastUserLocation = location
        
        // Update custom user location annotation if it exists
        if let userAnnotation = userLocationAnnotation {
            // Apply route snapping during navigation
            if isNavigating, let route = currentRoute {
                let snappedCoordinate = snapToRoute(userLocation: location, route: route)
                userAnnotation.coordinate = snappedCoordinate
            } else {
                userAnnotation.coordinate = location.coordinate
            }
        }
        
        // Only process during active navigation
        guard isNavigating,
              isAutoNavigationEnabled,
              let route = currentRoute,
              currentStepIndex < route.steps.count else {
            return
        }
        
        Task { @MainActor in
            checkStepProximity(userLocation: location)
            updateNavigationProgress(userLocation: location)
        }
    }
    
    private func handleHeadingUpdate(_ heading: CLHeading) {
        // Update custom user location annotation heading if it exists and we're navigating
        guard isNavigating, let userAnnotation = userLocationAnnotation else {
            return
        }
        
        // Post notification to trigger annotation view update
        NotificationCenter.default.post(
            name: NSNotification.Name("UserLocationHeadingUpdated"),
            object: userAnnotation
        )
    }
    
    private func checkStepProximity(userLocation: CLLocation) {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count - 1 else {
            // We're at the last step, check if we've reached destination
            checkDestinationReached(userLocation: userLocation)
            return
        }
        
        if currentStepIndex >= route.steps.count - 1 {
            return
        }
        
        let nextStep = route.steps[currentStepIndex + 1]
        
        // Get the coordinate for the end of current step (start of next step)
        let stepEndCoordinate = nextStep.polyline.coordinate
        let stepEndLocation = CLLocation(
            latitude: stepEndCoordinate.latitude,
            longitude: stepEndCoordinate.longitude
        )
        
        let distanceToStepEnd = userLocation.distance(from: stepEndLocation)
        
        // Auto-advance when close to the next instruction point
        if distanceToStepEnd <= proximityThreshold {
            nextStepFunction()
        }
    }
    
    private func checkDestinationReached(userLocation: CLLocation) {
        guard let destination = destination else { return }
        
        let destinationLocation = CLLocation(
            latitude: destination.placemark.coordinate.latitude,
            longitude: destination.placemark.coordinate.longitude
        )
        
        let distanceToDestination = userLocation.distance(from: destinationLocation)
        
        // Consider arrived when within 25 meters of destination
        if distanceToDestination <= 25.0 {
            // Could show arrival notification or auto-end navigation
        }
    }
    
    private func updateNavigationProgress(userLocation: CLLocation) {
        guard let route = currentRoute else { return }
        
        // Calculate remaining distance from current position to destination
        var totalRemainingDistance: CLLocationDistance = 0
        
        // Add distance from current location to the end of current step
        if currentStepIndex < route.steps.count {
            // Get the end coordinate of the current step
            let stepEndCoordinate: CLLocationCoordinate2D
            if currentStepIndex < route.steps.count - 1 {
                // Use the start of the next step as the end of current step
                stepEndCoordinate = route.steps[currentStepIndex + 1].polyline.coordinate
            } else {
                // For the last step, use the destination coordinate
                stepEndCoordinate = route.polyline.coordinate
            }
            
            let stepEndLocation = CLLocation(
                latitude: stepEndCoordinate.latitude,
                longitude: stepEndCoordinate.longitude
            )
            let distanceToStepEnd = userLocation.distance(from: stepEndLocation)
            totalRemainingDistance += distanceToStepEnd
            
            // Update current step remaining distance for UI display
            currentStepRemainingDistance = distanceToStepEnd
        }
        
        // Add distance of all remaining steps after the current one
        let remainingSteps = route.steps.dropFirst(currentStepIndex + 1)
        totalRemainingDistance += remainingSteps.reduce(0) { $0 + $1.distance }
        
        // Update remaining distance if it's different enough (to avoid constant updates)
        let distanceDifference = abs(remainingDistance - totalRemainingDistance)
        if distanceDifference > 10.0 { // Only update if change is more than 10 meters
            remainingDistance = totalRemainingDistance
            
            // Recalculate estimated time based on average speed
            if totalRemainingDistance > 0 {
                // Assume average speed of 50 km/h for time estimation
                let averageSpeedMPS = 50.0 * 1000.0 / 3600.0 // 50 km/h in m/s
                estimatedTimeRemaining = totalRemainingDistance / averageSpeedMPS
            }
            
            // Update LiveActivity with new progress
            updateLiveActivity()
        }
    }
    
    // MARK: - Search Functionality
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        // Note: Region will be set dynamically in search methods based on user location
    }
    
    func searchForPlaces(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        currentSearchTask?.cancel()
        isSearching = true
        
        currentSearchTask = Task {
            do {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                
                // Set region based on current location if available
                if let userLocation = lastUserLocation {
                    request.region = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        latitudinalMeters: 10000,
                        longitudinalMeters: 10000
                    )
                }
                
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                
                if !Task.isCancelled {
                    await MainActor.run {
                        self.searchResults = response.mapItems
                        self.isSearching = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
    
    func selectDestination(_ mapItem: MKMapItem) {
        destination = mapItem
        destinationCoordinate = mapItem.placemark.coordinate
        
        // Add to search history
        let historyItem = SearchHistoryItem(
            name: mapItem.name ?? "Unknown Location",
            address: mapItem.placemark.title ?? "",
            coordinate: mapItem.placemark.coordinate,
            timestamp: Date()
        )
        
        addToSearchHistory(historyItem)
        
        // Clear search results
        searchResults = []
        
        // Calculate route
        calculateRoute(to: mapItem)
    }
    
    // MARK: - Route Calculation
    
    func calculateRoute(to destination: MKMapItem) {
        // Cancel any existing route calculation
        cancelRouteCalculation()
        
        // Set loading state
        isCalculatingRoute = true
        routeCalculationError = nil
        
        guard let userLocation = lastUserLocation else {
            // Location not available yet, return early
            isCalculatingRoute = false
            routeCalculationError = "Location not available. Please wait for location to be determined."
            return
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        
        // Set up timeout timer (30 seconds)
        routeTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleRouteTimeout()
            }
        }
        
        currentRouteTask = Task {
            do {
                let response = try await directions.calculate()
                
                await MainActor.run {
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    self.isCalculatingRoute = false
                    self.routeTimeoutTimer?.invalidate()
                    self.routeTimeoutTimer = nil
                    
                    if let route = response.routes.first {
                        self.currentRoute = route
                        self.routePolyline = route.polyline
                        self.remainingDistance = route.distance
                        self.estimatedTimeRemaining = route.expectedTravelTime
                        self.updateAnnotations()
                        
                        // Trigger showing full route with both endpoints
                        self.shouldShowFullRoute = true
                        
                        self.routeCalculationError = nil
                    } else {
                        self.routeCalculationError = "No routes found"
                    }
                }
            } catch {
                await MainActor.run {
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    self.isCalculatingRoute = false
                    self.routeTimeoutTimer?.invalidate()
                    self.routeTimeoutTimer = nil
                    
                    if let mkError = error as? MKError {
                        self.routeCalculationError = mkError.localizedDescription
                    } else {
                        self.routeCalculationError = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Route Cancellation
    
    func cancelRouteCalculation() {
        // Cancel current task
        currentRouteTask?.cancel()
        currentRouteTask = nil
        
        // Cancel timeout timer
        routeTimeoutTimer?.invalidate()
        routeTimeoutTimer = nil
        
        // Reset loading state
        isCalculatingRoute = false
        routeCalculationError = nil
    }
    
    private func handleRouteTimeout() {
        // Cancel the current task
        currentRouteTask?.cancel()
        currentRouteTask = nil
        
        // Reset state
        isCalculatingRoute = false
        routeTimeoutTimer = nil
        routeCalculationError = "Route calculation timed out. Please try again."
    }
    
    private func updateAnnotations() {
        annotations.removeAll()
        
        // Add starting point annotation (user's current location)
        if let userLocation = lastUserLocation {
            let startAnnotation = MKPointAnnotation()
            startAnnotation.coordinate = userLocation.coordinate
            startAnnotation.title = "Starting Point"
            startAnnotation.subtitle = "Your current location"
            annotations.append(startAnnotation)
        }
        
        // Add destination annotation
        if let destination = destination {
            let destinationAnnotation = MKPointAnnotation()
            destinationAnnotation.coordinate = destination.placemark.coordinate
            destinationAnnotation.title = destination.name ?? "Destination"
            destinationAnnotation.subtitle = destination.placemark.title
            annotations.append(destinationAnnotation)
        }
    }
    
    // MARK: - Navigation Control
    
    func startNavigation() {
        guard let route = currentRoute else {
            return
        }
        
        isNavigating = true
        currentStepIndex = 0
        
        // Note: Heading updates are managed by the LocationManager instance in the main view
        
        // Create user location annotation for navigation
        if let userLocation = lastUserLocation {
            let userAnnotation = MKPointAnnotation()
            userAnnotation.coordinate = userLocation.coordinate
            userAnnotation.title = "Navigation Arrow"
            userLocationAnnotation = userAnnotation
        }
        
        // Trigger camera focus on starting point
        shouldFocusOnStartingPoint = true
        
        if !route.steps.isEmpty {
            currentStep = route.steps[0]
            
            // Start LiveActivity
            if let destination = destination {
                let startLocation = "Current Location" // You might want to get actual location name
                let currentInstruction = route.steps[0].instructions.isEmpty ? "Start navigation" : route.steps[0].instructions
                let maneuverType = liveActivityManager.getManeuverType(from: route.steps[0])
                
                liveActivityManager.startNavigationActivity(
                    startLocation: startLocation,
                    destinationName: destination.name ?? "Unknown Destination",
                    currentInstruction: currentInstruction,
                    remainingDistance: remainingDistance,
                    estimatedTimeRemaining: estimatedTimeRemaining,
                    currentStepIndex: currentStepIndex + 1, // Display as 1-based
                    totalSteps: route.steps.count,
                    maneuverType: maneuverType
                )
            }
        }
    }
    
    func stopNavigation() {
        isNavigating = false
        currentRoute = nil
        currentStep = nil
        currentStepIndex = 0
        remainingDistance = 0
        estimatedTimeRemaining = 0
        currentStepRemainingDistance = 0
        routePolyline = nil
        destination = nil
        destinationCoordinate = nil
        annotations.removeAll()
        userLocationAnnotation = nil // Clear user location annotation
        
        // End LiveActivity
        liveActivityManager.endNavigationActivity()
        
        // Reset zoom level to 50 meters when returning to home screen
        resetToHomeZoom()
    }
    
    private func resetToHomeZoom() {
        // Post notification to reset map zoom to 50 meters
        NotificationCenter.default.post(
            name: NSNotification.Name("ResetToHomeZoom"),
            object: nil
        )
    }
    
    func nextStepFunction() {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count - 1 else { return }
        
        currentStepIndex += 1
        currentStep = route.steps[currentStepIndex]
        
        // Reset current step remaining distance - it will be recalculated in next location update
        currentStepRemainingDistance = 0
        
        // Update remaining distance (simplified calculation)
        let remainingSteps = route.steps.dropFirst(currentStepIndex)
        remainingDistance = remainingSteps.reduce(0) { $0 + $1.distance }
        
        // Update LiveActivity
        updateLiveActivity()
    }
    
    func previousStepFunction() {
        guard let route = currentRoute,
              currentStepIndex > 0 else { return }
        
        currentStepIndex -= 1
        currentStep = route.steps[currentStepIndex]
        
        // Reset current step remaining distance - it will be recalculated in next location update
        currentStepRemainingDistance = 0
        
        // Update remaining distance (simplified calculation)
        let remainingSteps = route.steps.dropFirst(currentStepIndex)
        remainingDistance = remainingSteps.reduce(0) { $0 + $1.distance }
        
        // Update LiveActivity
        updateLiveActivity()
    }
    
    // Legacy function names for manual button control
    func nextStep() {
        nextStepFunction()
    }
    
    func previousStep() {
        previousStepFunction()
    }
    
    func toggleAutoNavigation() {
        isAutoNavigationEnabled.toggle()
    }
    
    // MARK: - Siri Integration Methods
    
    func startNavigation(to destination: String) {
        searchForPlaces(query: destination)
        
        // Auto-select first result if available
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let firstResult = self.searchResults.first {
                self.selectDestination(firstResult)
                self.startNavigation()
            }
        }
    }
    
    func searchLocation(query: String) {
        searchForPlaces(query: query)
    }
    
    // MARK: - LiveActivity Updates
    
    private func updateLiveActivity() {
        guard isNavigating,
              let route = currentRoute,
              let currentStep = currentStep,
              let destination = destination else { return }
        
        let currentInstruction = currentStep.instructions.isEmpty ? "Continue navigation" : currentStep.instructions
        let maneuverType = liveActivityManager.getManeuverType(from: currentStep)
        
        liveActivityManager.updateNavigationActivity(
            currentInstruction: currentInstruction,
            remainingDistance: remainingDistance,
            estimatedTimeRemaining: estimatedTimeRemaining,
            currentStepIndex: currentStepIndex + 1, // Display as 1-based
            totalSteps: route.steps.count,
            maneuverType: maneuverType,
            destinationName: destination.name ?? "Unknown Destination"
        )
    }
    
    // MARK: - Search History Management
    
    private func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: "SearchHistory"),
           let decoded = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) {
            searchHistory = decoded
        }
    }
    
    private func saveSearchHistory() {
        if let encoded = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(encoded, forKey: "SearchHistory")
        }
    }
    
    private func addToSearchHistory(_ item: SearchHistoryItem) {
        // Remove duplicates
        searchHistory.removeAll { $0.name == item.name }
        
        // Add to beginning
        searchHistory.insert(item, at: 0)
        
        // Keep only last 20 items
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        
        saveSearchHistory()
    }
    
    func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }
    
    func selectFromHistory(_ item: SearchHistoryItem) {
        let placemark = MKPlacemark(coordinate: item.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = item.name
        
        selectDestination(mapItem)
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension NavigationManager: MKLocalSearchCompleterDelegate {
    @preconcurrency nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Handle search completion suggestions if needed
    }
    
    @preconcurrency nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Search completer failed
    }
    
    // MARK: - Route Snapping
    
    private func snapToRoute(userLocation: CLLocation, route: MKRoute) -> CLLocationCoordinate2D {
        let userCoordinate = userLocation.coordinate
        let maxSnapDistance: CLLocationDistance = 10.0 // Maximum distance in meters to snap to route
        
        var closestPoint = userCoordinate
        var minDistance = Double.infinity
        
        // Get the route polyline coordinates
        let polyline = route.polyline
        var coordinates = Array<CLLocationCoordinate2D>(repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        
        // Find the closest point on the route
        for i in 0..<coordinates.count - 1 {
            let segmentStart = coordinates[i]
            let segmentEnd = coordinates[i + 1]
            
            // Find the closest point on this segment to the user location
            let closestPointOnSegment = closestPointOnLineSegment(
                point: userCoordinate,
                lineStart: segmentStart,
                lineEnd: segmentEnd
            )
            
            // Calculate distance from user to this closest point
            let distance = userLocation.distance(from: CLLocation(
                latitude: closestPointOnSegment.latitude,
                longitude: closestPointOnSegment.longitude
            ))
            
            if distance < minDistance {
                minDistance = distance
                closestPoint = closestPointOnSegment
            }
        }
        
        // Only snap if the user is within the maximum snap distance
        if minDistance <= maxSnapDistance {
            return closestPoint
        } else {
            // User is too far from route, return original position
            return userCoordinate
        }
    }
    
    private func closestPointOnLineSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        
        if dx == 0 && dy == 0 {
            // Line segment is just a point
            return lineStart
        }
        
        // Calculate the parameter t
        let t = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)
        
        // Clamp t to [0, 1] to stay within the line segment
        let clampedT = max(0, min(1, t))
        
        // Calculate the closest point
        let closestLat = lineStart.latitude + clampedT * dy
        let closestLon = lineStart.longitude + clampedT * dx
        
        return CLLocationCoordinate2D(latitude: closestLat, longitude: closestLon)
    }
}

// MARK: - Models
struct SearchHistoryItem: Codable, Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    
    private enum CodingKeys: String, CodingKey {
        case name, address, timestamp, latitude, longitude
    }
    
    init(name: String, address: String, coordinate: CLLocationCoordinate2D, timestamp: Date) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
}
