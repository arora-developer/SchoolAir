import SwiftUI

/// Physical sensors, regional weather, and sensor history stay separate.
struct RootView: View {
    enum Tab: String {
        case now, weather, history
    }

    /// Launch with `-tab history` (Xcode scheme arguments or `simctl launch`) to open on History.
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .now

    @State private var weather = WeatherStore()

    var body: some View {
        TabView(selection: $tab) {
            NowView()
                .tabItem { Label("Sensors", systemImage: "sensor.tag.radiowaves.forward") }
                .tag(Tab.now)
            Group {
                if tab == .weather { WeatherView(weather: weather) } else { Color.clear }
            }
                .tabItem { Label("Weather", systemImage: "cloud.sun") }
                .tag(Tab.weather)
            Group {
                if tab == .history { HistoryView() } else { Color.clear }
            }
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
                .tag(Tab.history)
        }
    }
}

#Preview {
    RootView()
        .environment(AirStore.preview)
}
