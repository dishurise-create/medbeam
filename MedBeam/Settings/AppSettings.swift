import SwiftUI
import Observation

/// User preferences, saved automatically.
@MainActor
@Observable
final class AppSettings {
    enum Theme: String, CaseIterable, Identifiable {
        case system = "System", light = "Light", dark = "Dark"
        var id: String { rawValue }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum Background: String, CaseIterable, Identifiable {
        case standard = "Default", mint = "Mint", sky = "Sky", lavender = "Lavender", peach = "Peach", sand = "Sand"
        var id: String { rawValue }
        var tint: Color {
            switch self {
            case .standard: return .clear
            case .mint: return Color(red: 0.20, green: 0.78, blue: 0.62)
            case .sky: return Color(red: 0.25, green: 0.56, blue: 0.95)
            case .lavender: return Color(red: 0.58, green: 0.45, blue: 0.92)
            case .peach: return Color(red: 0.98, green: 0.55, blue: 0.40)
            case .sand: return Color(red: 0.80, green: 0.66, blue: 0.42)
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case brand = "MedBeam", blue = "Blue", teal = "Teal", green = "Green", indigo = "Indigo", pink = "Pink", orange = "Orange"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .brand: return Brand.accent   // navy in light mode, gold in dark mode
            case .blue: return .blue
            case .teal: return .teal
            case .green: return .green
            case .indigo: return .indigo
            case .pink: return .pink
            case .orange: return .orange
            }
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small = "Small", standard = "Default", large = "Large", extraLarge = "Extra Large", huge = "Huge"
        var id: String { rawValue }
        var dynamicType: DynamicTypeSize {
            switch self {
            case .small: return .small
            case .standard: return .large
            case .large: return .xLarge
            case .extraLarge: return .xxLarge
            case .huge: return .accessibility1
            }
        }
    }

    var theme: Theme { didSet { save(theme.rawValue, "theme") } }
    var background: Background { didSet { save(background.rawValue, "background") } }
    var accent: Accent { didSet { save(accent.rawValue, "accent") } }
    var textSize: TextSize { didSet { save(textSize.rawValue, "textSize") } }

    init() {
        let d = UserDefaults.standard
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        background = Background(rawValue: d.string(forKey: "background") ?? "") ?? .standard
        accent = Accent(rawValue: d.string(forKey: "accent") ?? "") ?? .brand
        textSize = TextSize(rawValue: d.string(forKey: "textSize") ?? "") ?? .standard
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

// MARK: - Shared styling

/// Applies the chosen background color behind lists, forms and scroll views.
struct AppBackground: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Color(.systemGroupedBackground)
                    settings.background.tint.opacity(scheme == .dark ? 0.16 : 0.12)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }

    /// Rounded card used across the app.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
