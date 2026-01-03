import SwiftUI

@main
struct MoshiApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var hostManager = HostManager.shared
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(hostManager)
                .environmentObject(appSettings)
                .environmentObject(networkMonitor)
                .preferredColorScheme(appSettings.colorScheme)
        }
    }

    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
