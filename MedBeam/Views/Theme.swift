import SwiftUI
import UIKit

/// MedBeam's colors, taken from the app icon: night-sky navy and beam gold.
enum Brand {
    static let navyDark = Color(red: 0.055, green: 0.10, blue: 0.20)
    static let navy = Color(red: 0.12, green: 0.29, blue: 0.54)
    static let navyLight = Color(red: 0.18, green: 0.40, blue: 0.72)
    static let gold = Color(red: 1.0, green: 0.77, blue: 0.24)

    /// Accent for text and icons: navy on light backgrounds, gold on dark ones (both readable).
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.80, blue: 0.33, alpha: 1)
            : UIColor(red: 0.12, green: 0.29, blue: 0.54, alpha: 1)
    })

    /// Text color to put on top of a shape filled with `accent`.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.10, blue: 0.20, alpha: 1)
            : .white
    })

    static let buttonGradient = LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom)
}

/// The main button look: navy capsule with white text and a thin gold edge.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 22)
            .background(Brand.buttonGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.gold.opacity(0.55), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// A ring that fills to the percentage, with the number in the middle. Animates in.
struct PercentRing: View {
    let probability: Double
    let color: Color
    var size: CGFloat = 132
    var lineWidth: CGFloat = 13

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((shown * 100).rounded()))%")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = probability } }
        .onChange(of: probability) { _, new in withAnimation(.easeOut(duration: 0.5)) { shown = new } }
        .accessibilityHidden(true)
    }
}

/// A colored circle with the pharmacy's initials, so the list is easier to scan.
/// (Letters and colors only. These are not the companies' logos.)
struct PharmacyAvatar: View {
    let name: String
    var size: CGFloat = 42

    var body: some View {
        let text = Self.initials(name)
        Circle()
            .fill(Self.color(name).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(text)
                    .font(.system(size: size * (text.count >= 3 ? 0.30 : 0.40), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    /// "CVS Pharmacy" → CVS, "Harris Teeter Pharmacy" → HT, "Ted Pharmacy" → T
    static func initials(_ name: String) -> String {
        let skip: Set<String> = ["pharmacy", "drug", "drugs", "drugstore", "the", "and", "at", "of", "inc", "llc"]
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !skip.contains($0.lowercased()) }
        guard let first = words.first else { return "Rx" }
        if first.count <= 3 && first == first.uppercased() && first.contains(where: \.isLetter) { return first }
        return words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    static func color(_ name: String) -> Color {
        let n = name.lowercased()
        let known: [(String, Color)] = [
            ("cvs", Color(red: 0.80, green: 0.05, blue: 0.10)),
            ("walgreens", Color(red: 0.89, green: 0.12, blue: 0.24)),
            ("duane reade", Color(red: 0.89, green: 0.12, blue: 0.24)),
            ("walmart", Color(red: 0.0, green: 0.44, blue: 0.81)),
            ("costco", Color(red: 0.0, green: 0.36, blue: 0.66)),
            ("target", Color(red: 0.80, green: 0.0, blue: 0.0)),
            ("rite aid", Color(red: 0.0, green: 0.33, blue: 0.62)),
            ("giant", Color(red: 0.45, green: 0.18, blue: 0.56)),
            ("safeway", Color(red: 0.86, green: 0.16, blue: 0.14)),
            ("harris teeter", Color(red: 0.0, green: 0.48, blue: 0.30)),
            ("wegmans", Color(red: 0.16, green: 0.36, blue: 0.20)),
            ("kroger", Color(red: 0.05, green: 0.30, blue: 0.60)),
            ("publix", Color(red: 0.22, green: 0.54, blue: 0.24)),
            ("kaiser", Color(red: 0.0, green: 0.47, blue: 0.70)),
        ]
        if let match = known.first(where: { n.contains($0.0) }) { return match.1 }
        // Everyone else gets a steady color picked from the name
        let palette: [Color] = [.teal, .indigo, .orange, .mint, .purple, .brown, .cyan, .pink]
        let hash = n.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
