import SwiftUI

/// Three swipeable screens shown the first time the app opens.
struct WelcomeView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let text: String
    }

    private let pages = [
        Page(icon: "logo", title: "Find your medication",
             text: "Search any prescription and see which nearby pharmacies are most likely to have it."),
        Page(icon: "map.fill", title: "See your chances on a map",
             text: "Each pharmacy gets a percentage built from FDA and Medicaid data."),
        Page(icon: "person.3.fill", title: "Help your neighbors",
             text: "Tell MedBeam what you found. Reports are anonymous and make the estimates better for everyone."),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.navyDark, Brand.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            RadialGradient(colors: [Brand.gold.opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: onDone)
                        .foregroundStyle(.white.opacity(0.8))
                        .opacity(page < pages.count - 1 ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 22) {
                            Spacer()
                            Group {
                                if item.icon == "logo" {
                                    Image("Logo").resizable()
                                        .frame(width: 124, height: 124)
                                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
                                } else {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 54, weight: .semibold))
                                        .foregroundStyle(Brand.gold)
                                        .frame(width: 124, height: 124)
                                        .background(.white.opacity(0.12), in: Circle())
                                        .symbolEffect(.bounce, value: page == index)
                                }
                            }
                            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                            Text(item.title)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(item.text)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)
                            Spacer()
                            Spacer()
                        }
                        .tag(index)
                        .accessibilityElement(children: .combine)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Get started")
                        .font(.headline)
                        .foregroundStyle(Brand.navyDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Brand.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Text("Information only, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }
}
