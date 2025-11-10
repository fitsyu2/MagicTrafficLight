import WidgetKit
import SwiftUI

@main
struct MagicTrafficLightWidgetBundle: WidgetBundle {
    var body: some Widget {
        MagicTrafficLightWidget()
        if #available(iOS 16.1, *) {
            NavigationLiveActivity()
        }
    }
}