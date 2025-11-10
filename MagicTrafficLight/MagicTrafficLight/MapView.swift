//
//  MapView.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import SwiftUI
import MapKit
import UIKit

// Custom annotation for user location during navigation
class UserLocationAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    var heading: Double = 0.0
    
    init(coordinate: CLLocationCoordinate2D, heading: Double = 0.0) {
        self.coordinate = coordinate
        self.heading = heading
        self.title = "Your Location"
        super.init()
    }
}

struct MapView: UIViewRepresentable {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var navigationManager: NavigationManager
    @State private var mapView: MKMapView?
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Check if we're in landscape mode
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.mapType = .standard
        
        // Store reference for coordinator
        DispatchQueue.main.async {
            self.mapView = mapView
            context.coordinator.mapView = mapView
        }
        
        // Enable user interaction
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        
        // Set initial region with ultra-zoom
        mapView.setRegion(locationManager.region, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Prevent concurrent updates during camera animations
        guard !context.coordinator.isProgrammaticChange else { return }
        
        // Store reference for cleanup
        context.coordinator.mapView = mapView
        
        // Control user location display based on navigation state - with stability check
        let shouldShowUserLocation = !navigationManager.isNavigating
        if mapView.showsUserLocation != shouldShowUserLocation {
            // Prevent rapid toggling by adding a small delay
            DispatchQueue.main.async {
                if mapView.showsUserLocation != shouldShowUserLocation {
                    mapView.showsUserLocation = shouldShowUserLocation
                }
            }
        }
        
        // Camera following during navigation - with debouncing
        if navigationManager.isNavigating, let userLocation = locationManager.currentLocation {
            // Debounce rapid updates
            DispatchQueue.main.async {
                self.updateCameraForNavigation(mapView: mapView, userLocation: userLocation, context: context)
            }
        } else {
            // Reset camera behavior when not navigating - use standard region-based approach
            resetCameraForNonNavigation(mapView: mapView, context: context)
        }
        
        // One-time snap to user location when first available
        if !context.coordinator.hasSnappedToUser,
           let userLocation = locationManager.currentLocation {
            let userRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.00045, longitudeDelta: 0.00045)
            )
            mapView.setRegion(userRegion, animated: true)
            context.coordinator.hasSnappedToUser = true
        }
        
        // Handle camera focus on starting point when navigation starts
        if navigationManager.shouldFocusOnStartingPoint,
           let userLocation = locationManager.currentLocation {
            let startingRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
            )
            mapView.setRegion(startingRegion, animated: true)
            
            // Reset the flag
            DispatchQueue.main.async {
                navigationManager.shouldFocusOnStartingPoint = false
            }
        }
        
        // Handle showing full route after calculation
        if navigationManager.shouldShowFullRoute {
            showFullRoute(mapView: mapView)
            
            // Reset the flag
            DispatchQueue.main.async {
                navigationManager.shouldShowFullRoute = false
            }
        }
        
        // Update annotations only if they have changed
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        var newAnnotations = navigationManager.annotations
        
        // Add user location annotation during navigation only
        if navigationManager.isNavigating, 
           let userLocationAnnotation = navigationManager.userLocationAnnotation,
           !existingAnnotations.contains(where: { $0.title == "Navigation Arrow" }) {
            newAnnotations.append(userLocationAnnotation)
        }
        
        // Remove navigation arrow when not navigating
        if !navigationManager.isNavigating {
            let arrowAnnotations = existingAnnotations.filter { $0.title == "Navigation Arrow" }
            if !arrowAnnotations.isEmpty {
                mapView.removeAnnotations(arrowAnnotations)
            }
        }
        
        // Only update regular annotations if they are different
        let regularAnnotations = newAnnotations.filter { $0.title != "Navigation Arrow" }
        let existingRegularAnnotations = existingAnnotations.filter { $0.title != "Navigation Arrow" }
        
        if !annotationsEqual(existingRegularAnnotations, regularAnnotations) {
            mapView.removeAnnotations(existingRegularAnnotations)
            mapView.addAnnotations(regularAnnotations)
        }
        
        // Add navigation arrow separately to avoid conflicts
        if navigationManager.isNavigating,
           let userLocationAnnotation = navigationManager.userLocationAnnotation,
           !existingAnnotations.contains(where: { $0.title == "Navigation Arrow" }) {
            mapView.addAnnotation(userLocationAnnotation)
        }
        
        // Update route overlay only if it has changed
        let hasRouteOverlay = mapView.overlays.contains { $0 is MKPolyline }
        let shouldHaveRouteOverlay = navigationManager.routePolyline != nil
        
        if hasRouteOverlay != shouldHaveRouteOverlay || 
           (shouldHaveRouteOverlay && !overlaysEqual(mapView.overlays, navigationManager.routePolyline)) {
            
            mapView.removeOverlays(mapView.overlays)
            
            if let polyline = navigationManager.routePolyline {
                mapView.addOverlay(polyline)
                
                // No automatic route fitting - let user control map view
            }
        }
        
        // Stop cinematic movement if route preview starts
        if navigationManager.routePolyline != nil && context.coordinator.cinematicTimer != nil {
            context.coordinator.stopCinematicMovement()
        }
    }
    
    // Helper function to compare annotations
    private func annotationsEqual(_ existing: [MKAnnotation], _ new: [MKPointAnnotation]) -> Bool {
        guard existing.count == new.count else { return false }
        
        for (index, annotation) in existing.enumerated() {
            guard index < new.count,
                  let existingAnnotation = annotation as? MKPointAnnotation,
                  abs(existingAnnotation.coordinate.latitude - new[index].coordinate.latitude) < 0.00001,
                  abs(existingAnnotation.coordinate.longitude - new[index].coordinate.longitude) < 0.00001,
                  existingAnnotation.title == new[index].title else {
                return false
            }
        }
        return true
    }
    
    // Helper function to compare overlays
    private func overlaysEqual(_ existing: [MKOverlay], _ new: MKPolyline?) -> Bool {
        let polylineOverlays = existing.compactMap { $0 as? MKPolyline }
        
        if let newPolyline = new {
            return polylineOverlays.count == 1 && 
                   polylineOverlays.first?.pointCount == newPolyline.pointCount
        } else {
            return polylineOverlays.isEmpty
        }
    }
    
    // Method to show the full route with both start and end points visible
    private func showFullRoute(mapView: MKMapView) {
        guard let userLocation = locationManager.currentLocation,
              let destination = navigationManager.destination else {
            return
        }
        
        // Create coordinates array with start and end points
        let coordinates = [userLocation.coordinate, destination.placemark.coordinate]
        
        // Calculate region that includes both points
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3, // Add some padding
            longitudeDelta: (maxLon - minLon) * 1.3
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }
    
    // Camera following during navigation with UI-aware positioning
    private func updateCameraForNavigation(mapView: MKMapView, userLocation: CLLocation, context: Context) {
        // Prevent updates during animations or user interaction
        guard !context.coordinator.isProgrammaticChange,
              !context.coordinator.userIsInteracting else { return }
        
        // Reduce frequency check - make it more responsive for navigation
        let now = Date()
        if let lastUpdate = context.coordinator.lastCameraUpdate,
           now.timeIntervalSince(lastUpdate) < 1.5 { // Slightly increased for stability
            return
        }
        
        // Check if user has moved significantly before updating camera
        if let lastLocation = context.coordinator.lastCameraLocation {
            let distanceMoved = userLocation.distance(from: lastLocation)
            // Reduced minimum movement from 50 to 15 meters for responsive but stable navigation
            if distanceMoved < 15.0 {
                // Check heading change as well
                let currentHeading = locationManager.heading
                if let lastHeading = context.coordinator.lastCameraHeading {
                    let headingDifference = abs(currentHeading - lastHeading)
                    // Update if heading changed by more than 15 degrees
                    if headingDifference < 15.0 {
                        return
                    }
                }
            }
        }
        
        context.coordinator.lastCameraUpdate = now
        context.coordinator.lastCameraLocation = userLocation
        context.coordinator.lastCameraHeading = locationManager.heading
        
        performCameraUpdate(mapView: mapView, userLocation: userLocation, context: context)
    }
    
    // Perform the actual camera update for navigation mode
    private func performCameraUpdate(mapView: MKMapView, userLocation: CLLocation, context: Context) {
        // Safety check for valid map bounds
        guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
        
        // Use user location as center for navigation mode
        let userCoordinate = userLocation.coordinate
        
        // Validate coordinates
        guard CLLocationCoordinate2DIsValid(userCoordinate) else { return }
        
        // Set appropriate zoom level for navigation (keep current zoom if close enough)
        let currentRegion = mapView.region
        let navigationSpan = MKCoordinateSpan(
            latitudeDelta: 0.005, // About 500m view
            longitudeDelta: 0.005
        )
        
        // Use current zoom if it's reasonable, otherwise use navigation zoom
        let finalSpan: MKCoordinateSpan
        if currentRegion.span.latitudeDelta < 0.02 && currentRegion.span.latitudeDelta > 0.001 {
            finalSpan = currentRegion.span // Keep user's preferred zoom
        } else {
            finalSpan = navigationSpan // Use default navigation zoom
        }
        
        // Get user heading for map rotation
        let userHeading = locationManager.heading
        
        // Create camera with heading-based rotation centered on user location
        let camera = MKMapCamera(
            lookingAtCenter: userCoordinate,
            fromDistance: CLLocationDistance(finalSpan.latitudeDelta * 111320), // Convert degrees to meters approximately
            pitch: 0, // Keep flat view for navigation
            heading: userHeading // Rotate map to match user's heading
        )
        
        // Mark as programmatic change before animation
        context.coordinator.isProgrammaticChange = true
        
        // Use smooth but quick animation for camera movement
        UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            mapView.setCamera(camera, animated: false)
        } completion: { _ in
            // Reset flag after animation with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.coordinator.isProgrammaticChange = false
            }
        }
    }
    
    // Reset camera behavior when not navigating - use standard region approach
    private func resetCameraForNonNavigation(mapView: MKMapView, context: Context) {
        // Only reset if we were previously in navigation mode
        guard context.coordinator.lastCameraUpdate != nil else { return }
        
        // Clear navigation-specific camera tracking
        context.coordinator.lastCameraUpdate = nil
        context.coordinator.lastCameraLocation = nil
        
        // Reset to standard map orientation (no heading-based rotation)
        if let userLocation = locationManager.currentLocation {
            let currentRegion = mapView.region
            
            // Use current zoom level but remove rotation
            let standardRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: currentRegion.span
            )
            
            // Smoothly transition back to standard view
            UIView.animate(withDuration: 1.5, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                context.coordinator.isProgrammaticChange = true
                mapView.setRegion(standardRegion, animated: false)
                
                // Reset flag after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    context.coordinator.isProgrammaticChange = false
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Animation Configuration
    struct CinematicConfig {
        static let duration: TimeInterval = 60.0 * 5                    // Total movement duration in seconds
        static let frameRate: Double = 60.0                         // Animation frame rate (FPS)
        static let startDistance: Double = 0                    // Distance from center for start point (meters)
        static let endDistance: Double = 450                      // Distance from center for end point (meters)
        static let initialDelay: TimeInterval = 0.1
        static let interactionResetDelay: TimeInterval = 1.0        // Time to wait after user stops interacting
        static let restartDelay: TimeInterval = 3.0                 // Delay before restarting movement
        static let preserveUserZoom: Bool = true                    // Keep user's zoom level vs force specific zoom
        static let forcedZoomLevel: Double = 0.008                  // Zoom level when preserveUserZoom = false
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var hasSnappedToUser = false
        var lastCameraUpdate: Date?
        var lastCameraLocation: CLLocation?
        var lastCameraHeading: Double?
        var userIsInteracting: Bool = false
        var cinematicTimer: Timer? // Timer for cinematic camera movement
        var cinematicStartTime: Date? // Track when cinematic movement started
        var cinematicStartPoint: CLLocationCoordinate2D? // Starting point of cinematic movement
        var cinematicEndPoint: CLLocationCoordinate2D? // End point of cinematic movement
        var isProgrammaticChange: Bool = false // Flag to distinguish programmatic vs user changes
        var hasLoggedStop: Bool = false // Flag to prevent multiple stop log messages
        weak var mapView: MKMapView?
        
        init(_ parent: MapView) {
            self.parent = parent
            super.init()
            
            // Listen for heading updates to refresh arrow annotation
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UserLocationHeadingUpdated"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let mapView = self.mapView,
                      let heading = notification.object as? CLHeading else { return }
                
                // Get the adjusted heading for current device orientation
                let adjustedHeading = self.getAdjustedHeading(heading)
                
                // Update all navigation arrow annotations with the new heading
                for annotation in mapView.annotations {
                    if let pointAnnotation = annotation as? MKPointAnnotation,
                       pointAnnotation.title == "Navigation Arrow",
                       let annotationView = mapView.view(for: annotation) {
                        
                        let arrowImage = self.createArrowImage(heading: adjustedHeading)
                        annotationView.image = arrowImage
                    }
                }
            }
            
            // Listen for home zoom reset when navigation ends
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ResetToHomeZoom"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let mapView = self.mapView else { return }
                
                // Reset to 50 meter zoom level
                self.resetToHomeZoomLevel(mapView: mapView)
            }
        }
        
        deinit {
            // Clean up cinematic timer to prevent memory leaks
            stopCinematicMovement()
            NotificationCenter.default.removeObserver(self)
            
            // Clear references
            mapView = nil
        }
        
        // Get adjusted heading based on device orientation
        private func getAdjustedHeading(_ heading: CLHeading) -> Double {
            let rawHeading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            let orientation = UIDevice.current.orientation
            var adjustedHeading = rawHeading
            
            switch orientation {
            case .landscapeLeft:
                // When device is rotated left (home button on right), compass needs +90 degrees
                adjustedHeading = (rawHeading + 90).truncatingRemainder(dividingBy: 360)
            case .landscapeRight:
                // When device is rotated right (home button on left), compass needs -90 degrees
                adjustedHeading = (rawHeading - 90 + 360).truncatingRemainder(dividingBy: 360)
            case .portraitUpsideDown:
                // When device is upside down, compass needs +180 degrees
                adjustedHeading = (rawHeading + 180).truncatingRemainder(dividingBy: 360)
            default:
                // Portrait and other orientations - no adjustment needed
                adjustedHeading = rawHeading
            }
            
            return adjustedHeading
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 5.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Handle built-in user location (when not navigating)
            if annotation is MKUserLocation {
                return nil // Use default user location view
            }
            
            // Handle custom user location annotation during navigation (our arrow)
            if let pointAnnotation = annotation as? MKPointAnnotation,
               pointAnnotation.title == "Navigation Arrow",
               parent.navigationManager.isNavigating {
                
                let identifier = "NavigationArrow"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.frame.size = CGSize(width: 30, height: 30)
                    annotationView?.centerOffset = CGPoint(x: 0, y: -15)
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Create and set arrow image with current heading adjusted for orientation
                let currentHeading = parent.locationManager.heading
                let arrowImage = createArrowImage(heading: currentHeading)
                annotationView?.image = arrowImage
                
                return annotationView
            }
            
            // Handle regular annotations (start/end points)
            let identifier = "CustomPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            // Different colors for start and end points
            if let title = annotation.title, title == "Starting Point" {
                annotationView?.markerTintColor = .systemGreen
                annotationView?.glyphText = "🚀"
            } else {
                annotationView?.markerTintColor = .systemRed
                annotationView?.glyphText = "📍"
            }
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            // Update location manager when user location changes
            if let location = userLocation.location {
                DispatchQueue.main.async {
                    self.parent.locationManager.location = location
                }
            }
        }
        
        // Create custom arrow image for navigation
        private func createArrowImage(heading: Double = 0.0) -> UIImage {
            let size = CGSize(width: 24, height: 24)
            let renderer = UIGraphicsImageRenderer(size: size)
            
            return renderer.image { context in
                let cgContext = context.cgContext
                
                // Apply rotation transformation based on heading
                cgContext.translateBy(x: size.width/2, y: size.height/2)
                cgContext.rotate(by: CGFloat(heading * .pi / 180)) // Direct heading rotation - no offset needed
                cgContext.translateBy(x: -size.width/2, y: -size.height/2)
                
                // Create simple triangle arrow pointing up (north)
                let trianglePath = UIBezierPath()
                
                // Triangle vertices - pointing up
                let topPoint = CGPoint(x: size.width/2, y: 3)      // Top point
                let leftPoint = CGPoint(x: 4, y: size.height - 3)   // Bottom left
                let rightPoint = CGPoint(x: size.width - 4, y: size.height - 3) // Bottom right
                
                trianglePath.move(to: topPoint)
                trianglePath.addLine(to: leftPoint)
                trianglePath.addLine(to: rightPoint)
                trianglePath.close()
                
                // Fill triangle with bright blue color
                cgContext.setFillColor(UIColor.systemBlue.cgColor)
                cgContext.addPath(trianglePath.cgPath)
                cgContext.fillPath()
                
                // Add white border for better visibility
                cgContext.setStrokeColor(UIColor.white.cgColor)
                cgContext.setLineWidth(1.5)
                cgContext.addPath(trianglePath.cgPath)
                cgContext.strokePath()
            }
        }
        
        // Track user interaction to avoid interrupting manual map control
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Skip interaction detection if this is a programmatic change
            guard !isProgrammaticChange else {
                return
            }
            
            // Safely check for user interaction
            if let lastUpdate = lastCameraUpdate {
                if Date().timeIntervalSince(lastUpdate) > 0.5 {
                    userIsInteracting = true
                    
                    // Stop cinematic movement immediately when user interacts
                    if cinematicTimer != nil {
                        print("👆 User interaction detected - stopping cinematic movement")
                        stopCinematicMovement()
                    }
                }
            } else {
                userIsInteracting = true
                
                // Stop cinematic movement when user first interacts
                if cinematicTimer != nil {
                    print("👆 User interaction detected - stopping cinematic movement")
                    stopCinematicMovement()
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Skip interaction reset if this is a programmatic change
            guard !isProgrammaticChange else {
                return
            }
            
            // Reset interaction flag after configured delay
            DispatchQueue.main.asyncAfter(deadline: .now() + CinematicConfig.interactionResetDelay) {
                self.userIsInteracting = false
                
                // Restart cinematic movement if conditions are met and no navigation or route preview
                if !self.parent.navigationManager.isNavigating,
                   self.parent.navigationManager.routePolyline == nil, // Don't restart during route preview
                   self.parent.locationManager.initialLocation != nil,
                   self.cinematicTimer == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + CinematicConfig.restartDelay) {
                        if !self.userIsInteracting && !self.parent.navigationManager.isNavigating {
                            self.startCinematicMovement(mapView: mapView)
                        }
                    }
                }
            }
        }
        
        // Start cinematic camera movement across the map
        func startCinematicMovement(mapView: MKMapView) {
            guard !parent.navigationManager.isNavigating,
                  parent.navigationManager.routePolyline == nil, // Don't start during route preview
                  let initialLocation = parent.locationManager.initialLocation,
                  !userIsInteracting else {
                print("⏹️ Skipping cinematic movement - conditions not met")
                return
            }
            
            // Reset the stop logging flag for the new session
            hasLoggedStop = false
            
            // Get user's heading (facing direction)
            let userHeading = parent.locationManager.heading
            print("🎬 Starting cinematic movement with heading: \(userHeading)°")
            
            // Calculate start and end points of the cinematic movement
            // Start from one end of the radius opposite to facing direction
            let startHeading = (userHeading + 180).truncatingRemainder(dividingBy: 360)
            let endHeading = userHeading
            
            cinematicStartPoint = calculateTargetCoordinate(
                from: initialLocation.coordinate,
                heading: startHeading,
                distance: CinematicConfig.startDistance
            )
            
            cinematicEndPoint = calculateTargetCoordinate(
                from: initialLocation.coordinate,
                heading: endHeading,
                distance: CinematicConfig.endDistance
            )
            
            cinematicStartTime = Date()
            
            // Start the cinematic timer using configured frame rate
            let frameInterval = 1.0 / CinematicConfig.frameRate
            cinematicTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                self?.updateCinematicMovement(mapView: mapView)
            }
            
            print("🎬 Cinematic movement started from \(cinematicStartPoint!) to \(cinematicEndPoint!) (\(CinematicConfig.duration)s duration)")
        }
        
        // Stop cinematic camera movement
        func stopCinematicMovement() {
            guard cinematicTimer != nil else {
                return // Already stopped, no need to log again
            }
            
            cinematicTimer?.invalidate()
            cinematicTimer = nil
            cinematicStartTime = nil
            cinematicStartPoint = nil
            cinematicEndPoint = nil
            hasLoggedStop = false // Reset for next time
            print("⏹️ Cinematic movement stopped")
        }
        
        // Update cinematic camera position
        func updateCinematicMovement(mapView: MKMapView) {
            guard let startTime = cinematicStartTime,
                  let startPoint = cinematicStartPoint,
                  let endPoint = cinematicEndPoint,
                  !userIsInteracting,
                  parent.navigationManager.routePolyline == nil else { // Stop if route preview starts
                // Only stop if we haven't already logged it this session
                if !hasLoggedStop {
                    hasLoggedStop = true
                    stopCinematicMovement()
                }
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / CinematicConfig.duration, 1.0)
            
            // Use easeInOut for smooth movement
            let easedProgress = easeInOut(progress)
            
            // Interpolate between start and end points
            let currentLat = startPoint.latitude + (endPoint.latitude - startPoint.latitude) * easedProgress
            let currentLon = startPoint.longitude + (endPoint.longitude - startPoint.longitude) * easedProgress
            let currentCenter = CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon)
            
            // Use zoom configuration
            let regionSpan: MKCoordinateSpan
            if CinematicConfig.preserveUserZoom {
                regionSpan = mapView.region.span  // Keep user's current zoom
            } else {
                regionSpan = MKCoordinateSpan(    // Force specific zoom level
                    latitudeDelta: CinematicConfig.forcedZoomLevel,
                    longitudeDelta: CinematicConfig.forcedZoomLevel
                )
            }
            
            let region = MKCoordinateRegion(center: currentCenter, span: regionSpan)
            
            // Mark as programmatic change to avoid triggering user interaction detection
            isProgrammaticChange = true
            mapView.setRegion(region, animated: false)
            
            // Reset flag after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isProgrammaticChange = false
            }
            
            // Stop when movement is complete
            if progress >= 1.0 {
                print("🎬 Cinematic movement completed")
                stopCinematicMovement()
            }
        }
        
        // Easing function for smooth movement
        func easeInOut(_ t: Double) -> Double {
            return t * t * (3.0 - 2.0 * t)
        }
        
        // Calculate coordinate at distance and heading from a point
        func calculateTargetCoordinate(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection, distance: Double) -> CLLocationCoordinate2D {
            let earthRadius = 6371000.0 // Earth radius in meters
            let headingRadians = heading * .pi / 180.0
            
            let lat1 = coordinate.latitude * .pi / 180.0
            let lon1 = coordinate.longitude * .pi / 180.0
            
            let lat2 = asin(sin(lat1) * cos(distance / earthRadius) + 
                           cos(lat1) * sin(distance / earthRadius) * cos(headingRadians))
            
            let lon2 = lon1 + atan2(sin(headingRadians) * sin(distance / earthRadius) * cos(lat1),
                                   cos(distance / earthRadius) - sin(lat1) * sin(lat2))
            
            return CLLocationCoordinate2D(
                latitude: lat2 * 180.0 / .pi,
                longitude: lon2 * 180.0 / .pi
            )
        }
        
        // Reset map zoom to 50 meter level when returning to home screen
        func resetToHomeZoomLevel(mapView: MKMapView) {
            guard let userLocation = parent.locationManager.currentLocation else { return }
            
            // Set zoom level to 50 meters (0.00045 span)
            let homeZoomRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.00045, longitudeDelta: 0.00045)
            )
            
            // Animate to home zoom level
            UIView.animate(withDuration: 1.5, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                mapView.setRegion(homeZoomRegion, animated: false)
            }
            
            print("🏠 Reset to home zoom level (50 meters)")
        }
    }
}
