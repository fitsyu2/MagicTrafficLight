//
//  WidgetBundle.swift
//  Widget
//
//  Created by Fitrah Syuhada on 01/11/25.
//

import WidgetKit
import SwiftUI

@main
struct MagicTrafficLightWidgetBundle: WidgetBundle {
    var body: some Widget {
        MagicTrafficLightWidget()
        NavigationLiveActivity()
        TrafficLightLiveActivity()
    }
}
