import SwiftUI

/// Entry point. The app lives only in the menu bar (LSUIElement = YES hides the Dock icon).
@main
struct ProximityWatchApp: App {
    @StateObject private var monitor = WatchMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuView(monitor: monitor)
        } label: {
            Image(systemName: monitor.state.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
