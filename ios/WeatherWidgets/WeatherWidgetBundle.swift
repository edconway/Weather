import SwiftUI
import WidgetKit

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        LockScreenConditionsWidget()
        LockScreenAnomalyWidget()
        LockScreenRainWidget()
    }
}
