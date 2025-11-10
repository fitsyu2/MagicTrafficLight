//
//  LocationManager.swift
//  MagicTrafficLight
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import Foundation
import CoreLocation
import MapKit
import UIKit

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var location: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -6.2441, longitude: 106.7991), // Pasaraya Blok M default
        span: MKCoordinateSpan(latitudeDelta: 0.00045, longitudeDelta: 0.00045)
    )
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationPermissionGranted = false
    @Published var isUpdatingLocation = false
    @Published var heading: CLLocationDirection = 0.0
    @Published var isHeadingAvailable = false
    @Published var capturedHeading: CLLocationDirection?
    @Published var targetLocation: CLLocationCoordinate2D?
    @Published var currentHeading: CLHeading? // Add current heading for navigation
    @Published var initialLocation: CLLocation? // Store the first location received
    @Published var radiusRegion: MKCoordinateRegion? // 1000m radius around initial location
    
    private var hasReachedTarget = false
    private var hasSetInitialUserRegion = false
    private var hasSetInitialLocation = false // Track if we've captured the first location
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        
        // Check heading availability
        isHeadingAvailable = CLLocationManager.headingAvailable()
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            isLocationPermissionGranted = true
            startLocationUpdates()
        } else if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        isUpdatingLocation = true
        locationManager.startUpdatingLocation()
        
        // Start heading updates if available
        if isHeadingAvailable {
            locationManager.startUpdatingHeading()
        }
    }
    
    func stopLocationUpdates() {
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }
    
    func requestCurrentLocation() {
        guard isLocationPermissionGranted else {
            requestLocationPermission()
            return
        }
        locationManager.requestLocation()
    }
    
    func getCurrentLocation() -> CLLocationCoordinate2D? {
        return currentLocation?.coordinate
    }
    
    func startUpdatingHeading() {
        guard isLocationPermissionGranted else {
            requestLocationPermission()
            return
        }
        locationManager.startUpdatingHeading()
    }
    
    // Calculate a 1000-meter radius region around a given location
    func calculateRadiusRegion(around location: CLLocation, radiusInMeters: Double = 1000.0) -> MKCoordinateRegion {
        let coordinateRegion = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusInMeters * 2, // diameter
            longitudinalMeters: radiusInMeters * 2  // diameter
        )
        return coordinateRegion
    }
    
    // Get coordinates for the boundary of the 1000m radius
    func getRadiusCoordinates(around location: CLLocation, radiusInMeters: Double = 1000.0) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let numberOfPoints = 36 // Creates a circle with 36 points (every 10 degrees)
        
        for i in 0..<numberOfPoints {
            let angle = Double(i) * 360.0 / Double(numberOfPoints)
            let coordinate = calculateTargetCoordinate(
                from: location.coordinate,
                heading: angle,
                distance: radiusInMeters
            )
            coordinates.append(coordinate)
        }
        
        return coordinates
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        location = newLocation
        currentLocation = newLocation
        
        // Capture the first location and calculate 1000m radius region
        if !hasSetInitialLocation {
            hasSetInitialLocation = true
            initialLocation = newLocation
            radiusRegion = calculateRadiusRegion(around: newLocation, radiusInMeters: 1000.0)
            
            print("📍 Initial location captured: \(newLocation.coordinate)")
            print("🔵 1000m radius region calculated: \(radiusRegion!)")
            
            // Notify about initial location with radius
            NotificationCenter.default.post(
                name: NSNotification.Name("InitialLocationCaptured"),
                object: [
                    "location": newLocation,
                    "radiusRegion": radiusRegion!,
                    "radiusCoordinates": getRadiusCoordinates(around: newLocation)
                ]
            )
        }
        
        // Notify NavigationManager of location updates for auto-navigation
        NotificationCenter.default.post(
            name: NSNotification.Name("LocationDidUpdate"),
            object: newLocation
        )
        
        // No automatic region updates - MapView handles initial snap
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location manager failed
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        isLocationPermissionGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        
        if isLocationPermissionGranted {
            startLocationUpdates()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Always update current heading for navigation
        currentHeading = newHeading
        
        // Get the raw heading value
        let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        // Adjust heading based on device orientation (for landscape mode)
        let adjustedHeading = adjustHeadingForOrientation(rawHeading)
        heading = adjustedHeading
        
        // Notify MapView of heading updates for arrow rotation
        NotificationCenter.default.post(
            name: NSNotification.Name("UserLocationHeadingUpdated"),
            object: newHeading
        )
        
        // Only capture initial heading once for route calculation
        guard newHeading.headingAccuracy >= 0,
              capturedHeading == nil else {
            return
        }

        let headingValue = newHeading.magneticHeading
        capturedHeading = headingValue
        
        // Calculate target location 100 meters ahead in the heading direction
        if let currentLoc = currentLocation {
            let targetCoord = calculateTargetCoordinate(
                from: currentLoc.coordinate,
                heading: headingValue,
                distance: 100.0 // 100 meters
            )
            targetLocation = targetCoord
        }
        
        // Don't stop heading updates - keep them for continuous arrow rotation
        // locationManager.stopUpdatingHeading() // Commented out to keep heading updates active
    }
    
    // Adjust heading based on device orientation
    private func adjustHeadingForOrientation(_ heading: CLLocationDirection) -> CLLocationDirection {
        let orientation = UIDevice.current.orientation
        var adjustedHeading = heading
        
        switch orientation {
        case .landscapeLeft:
            // When device is rotated left (home button on right), compass needs +90 degrees
            adjustedHeading = (heading + 90).truncatingRemainder(dividingBy: 360)
        case .landscapeRight:
            // When device is rotated right (home button on left), compass needs -90 degrees
            adjustedHeading = (heading - 90 + 360).truncatingRemainder(dividingBy: 360)
        case .portraitUpsideDown:
            // When device is upside down, compass needs +180 degrees
            adjustedHeading = (heading + 180).truncatingRemainder(dividingBy: 360)
        default:
            // Portrait and other orientations - no adjustment needed
            adjustedHeading = heading
        }
        
        return adjustedHeading
    }
    
    // Calculate coordinate 100 meters ahead in the given heading direction
    private func calculateTargetCoordinate(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection, distance: Double) -> CLLocationCoordinate2D {
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
    
    // Reset captured heading to allow new capture
    func resetCapturedHeading() {
        capturedHeading = nil
        targetLocation = nil
        hasReachedTarget = false
        
        // No automatic region updates - let user control map positioning
        
        // Restart heading updates to capture new heading
        if isHeadingAvailable && isLocationPermissionGranted {
            locationManager.startUpdatingHeading()
        }
    }
    
    // Reset initial location to capture a new 1000m radius area
    func resetInitialLocation() {
        hasSetInitialLocation = false
        initialLocation = nil
        radiusRegion = nil
        
        print("🔄 Initial location reset - will capture new 1000m radius on next location update")
    }
}