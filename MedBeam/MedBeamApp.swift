import SwiftUI

@main
struct MedBeamApp: App {
    @State private var settings: AppSettings
    @State private var appState: AppState

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _appState = State(initialValue: AppState(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(settings)
                .tint(settings.accent.color)
                .preferredColorScheme(settings.theme.colorScheme)
                .dynamicTypeSize(settings.textSize.dynamicType)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.selectedTab) {
            NavigationStack(path: $app.homePath) {
                HomeView()
                    .navigationDestination(for: AppState.Route.self) { route in
                        switch route {
                        case .results: ResultsView()
                        }
                    }
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppState.Tab.home)

            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppState.Tab.history)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppState.Tab.settings)
        }
    }
}
