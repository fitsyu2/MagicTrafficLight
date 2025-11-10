import Foundation
import Intents

// MARK: - Start Navigation Intent
@available(iOS 12.0, *)
public class StartNavigationIntent: INIntent {
    @NSManaged public var destination: String?
    @NSManaged public var useCurrentLocation: NSNumber?
    
    public convenience init(destination: String?, useCurrentLocation: Bool = true) {
        self.init()
        self.destination = destination
        self.useCurrentLocation = NSNumber(value: useCurrentLocation)
    }
}

// MARK: - Stop Navigation Intent
@available(iOS 12.0, *)
public class StopNavigationIntent: INIntent {
    public override init() {
        super.init()
    }
}

// MARK: - Search Location Intent
@available(iOS 12.0, *)
public class SearchLocationIntent: INIntent {
    @NSManaged public var searchQuery: String?
    
    public convenience init(searchQuery: String?) {
        self.init()
        self.searchQuery = searchQuery
    }
}

// MARK: - Intent Responses
@available(iOS 12.0, *)
public class StartNavigationIntentResponse: INIntentResponse {
    public enum Code: Int {
        case unspecified = 0
        case ready = 1
        case continueInApp = 2
        case inProgress = 3
        case success = 4
        case failure = 5
        case failureRequiringAppLaunch = 6
        case failureAppConfigurationRequired = 7
    }
    
    @NSManaged public var code: Code
    @NSManaged public var userActivity: NSUserActivity?
    
    public convenience init(code: Code, userActivity: NSUserActivity?) {
        self.init()
        self.code = code
        self.userActivity = userActivity
    }
}

@available(iOS 12.0, *)
public class StopNavigationIntentResponse: INIntentResponse {
    public enum Code: Int {
        case unspecified = 0
        case ready = 1
        case continueInApp = 2
        case inProgress = 3
        case success = 4
        case failure = 5
    }
    
    @NSManaged public var code: Code
    
    public convenience init(code: Code) {
        self.init()
        self.code = code
    }
}

@available(iOS 12.0, *)
public class SearchLocationIntentResponse: INIntentResponse {
    public enum Code: Int {
        case unspecified = 0
        case ready = 1
        case continueInApp = 2
        case inProgress = 3
        case success = 4
        case failure = 5
        case failureRequiringAppLaunch = 6
    }
    
    @NSManaged public var code: Code
    @NSManaged public var results: [String]?
    
    public convenience init(code: Code, results: [String]? = nil) {
        self.init()
        self.code = code
        self.results = results
    }
}