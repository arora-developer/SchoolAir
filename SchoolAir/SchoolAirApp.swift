import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct SchoolAirApp: App {
    
    init() {
        FirebaseApp.configure()
    
    }
    /// The app's one store. Swap the reading source here and nothing else changes:
    /// - `PlaceholderReadingSource()` while the boxes are being built (now).
    /// - `FirebaseReadingSource()` once the boxes post real readings (see that file for the steps).
    /// - `RecordedReadingSource(url:)` for a labelled replay during the video.
    @State private var store: AirStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            return AirStore.preview
        }
        #endif
        return AirStore(readings: FirebaseReadingSource(), airNow: AirNowProvider.makeDefault(), events: EventStore())
    }()

    /// Launch arguments: `-splash off` skips the splash, `-splash hold` keeps it (screenshots).
    @State private var showSplash = UserDefaults.standard.string(forKey: "splash") != "off"

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(store)
                    .task(id: store.connectionAttempt) { await store.start() }

                if showSplash {
                    SplashView(holds: UserDefaults.standard.string(forKey: "splash") == "hold") {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
