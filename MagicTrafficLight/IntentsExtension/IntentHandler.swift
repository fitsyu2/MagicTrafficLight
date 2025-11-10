import Foundation
import Intents

@available(iOS 12.0, *)
class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any {
        switch intent {
        case is StartNavigationIntent:
            return StartNavigationIntentHandler()
        case is StopNavigationIntent:
            return StopNavigationIntentHandler()
        case is SearchLocationIntent:
            return SearchLocationIntentHandler()
        default:
            fatalError("Unhandled intent type: \(intent)")
        }
    }
}

// MARK: - Start Navigation Handler
@available(iOS 12.0, *)
class StartNavigationIntentHandler: NSObject, StartNavigationIntentHandling {
    
    func handle(intent: StartNavigationIntent, completion: @escaping (StartNavigationIntentResponse) -> Void) {
        guard let destination = intent.destination, !destination.isEmpty else {
            completion(StartNavigationIntentResponse(code: .failure, userActivity: nil))
            return
        }
        
        // Create user activity to pass to main app
        let userActivity = NSUserActivity(activityType: "com.magictrafficlight.startNavigation")
        userActivity.title = "Start Navigation to \(destination)"
        userActivity.userInfo = [
            "destination": destination,
            "useCurrentLocation": intent.useCurrentLocation?.boolValue ?? true
        ]
        userActivity.isEligibleForSearch = true
        userActivity.isEligibleForHandoff = true
        
        completion(StartNavigationIntentResponse(code: .continueInApp, userActivity: userActivity))
    }
    
    func resolveDestination(for intent: StartNavigationIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let destination = intent.destination, !destination.isEmpty else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        
        completion(INStringResolutionResult.success(with: destination))
    }
}

// MARK: - Stop Navigation Handler
@available(iOS 12.0, *)
class StopNavigationIntentHandler: NSObject, StopNavigationIntentHandling {
    
    func handle(intent: StopNavigationIntent, completion: @escaping (StopNavigationIntentResponse) -> Void) {
        // Create user activity to stop navigation in main app
        let userActivity = NSUserActivity(activityType: "com.magictrafficlight.stopNavigation")
        userActivity.title = "Stop Navigation"
        userActivity.isEligibleForSearch = true
        userActivity.isEligibleForHandoff = true
        
        let response = StopNavigationIntentResponse(code: .continueInApp)
        response.userActivity = userActivity
        completion(response)
    }
}

// MARK: - Search Location Handler
@available(iOS 12.0, *)
class SearchLocationIntentHandler: NSObject, SearchLocationIntentHandling {
    
    func handle(intent: SearchLocationIntent, completion: @escaping (SearchLocationIntentResponse) -> Void) {
        guard let searchQuery = intent.searchQuery, !searchQuery.isEmpty else {
            completion(SearchLocationIntentResponse(code: .failure, results: nil))
            return
        }
        
        // Create user activity to search in main app
        let userActivity = NSUserActivity(activityType: "com.magictrafficlight.searchLocation")
        userActivity.title = "Search for \(searchQuery)"
        userActivity.userInfo = ["searchQuery": searchQuery]
        userActivity.isEligibleForSearch = true
        userActivity.isEligibleForHandoff = true
        
        let response = SearchLocationIntentResponse(code: .continueInApp, results: [searchQuery])
        response.userActivity = userActivity
        completion(response)
    }
    
    func resolveSearchQuery(for intent: SearchLocationIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let searchQuery = intent.searchQuery, !searchQuery.isEmpty else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        
        completion(INStringResolutionResult.success(with: searchQuery))
    }
}