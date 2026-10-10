import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let trend = app.localTrend

        List {
            if let med = app.selectedMedication {
                Section {
                    Text(med.shortName).font(.headline)
                }
            }

            SupplyRiskSection(risk: app.supplyRisk, isLoading: app.isLoadingSupplyRisk)

            // 1. OFFICIAL — from the FDA
            if let shortage = app.shortage {
                Section {
                    ShortageChip(level: shortage.level)
                    if let posted = shortage.initialPostingDate {
                        LabeledContent("Shortage first posted", value: posted.formatted(date: .abbreviated, time: .omitted))
                    }
                    ForEach(shortage.manufacturers) { maker in
                        HStack {
                            Text(maker.company).font(.subheadline)
                            Spacer()
                            Text(maker.category.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(color(for: maker.category))
                        }
                    }
                    if shortage.level == .none {
                        Text("No matching entry in the FDA Drug Shortages database for this strength and form.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    SourceHeader(title: "National status", source: "Official · FDA")
                }
            }

            // 2. DETECTED — from community reports
            Section {
                HStack {
                    Image(systemName: trend.direction.symbol)
                        .font(.title2.bold())
                        .foregroundStyle(directionColor(trend.direction))
                    VStack(alignment: .leading) {
                        Text("Local availability").font(.caption).foregroundStyle(.secondary)
                        Text(trend.direction.rawValue).font(.title3.bold())
                    }
                    Spacer()
                    if trend.usesSimulatedData { SimulatedBadge() }
                }

                if !trend.points.isEmpty {
                    Chart(trend.points) { point in
                        LineMark(x: .value("Week", point.label), y: .value("Had it", point.rate * 100))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Week", point.label), y: .value("Had it", point.rate * 100))
                            .annotation(position: .top) {
                                Text("\(Int(point.rate * 100))%").font(.caption2)
                            }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxisLabel("% of reports: \"had it\"")
                    .frame(height: 200)
                    .padding(.vertical, 8)

                    ForEach(trend.points.reversed()) { point in
                        LabeledContent(point.label, value: "\(Int(point.rate * 100))%  (\(point.reportCount) reports)")
                            .font(.subheadline)
                    }
                } else {
                    Text("Trends appear once there are at least \(TrendAnalyzer.minReportsPerWeek) reports per week near \(app.zip).")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if let warning = trend.earlyWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            } header: {
                SourceHeader(title: "Near \(app.zip)", source: "Detected by MedBeam")
            } footer: {
                Text("Local trends come from anonymous reports and our model. A local decline is NOT the same as an official FDA shortage.")
            }

            Section("What these mean") {
                LegendRow(color: .red, title: "Official FDA shortage", detail: "The FDA has confirmed a national shortage.")
                LegendRow(color: .orange, title: "Local decline", detail: "Fewer people nearby are finding it. Detected by MedBeam, not confirmed by the FDA.")
                LegendRow(color: .gray, title: "One pharmacy out", detail: "A single pharmacy was temporarily out of stock.")
            }
        }
        .appBackground()
        .navigationTitle("Medication trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for category: ManufacturerSupply.Category) -> Color {
        switch category {
        case .available: return .green
        case .limited: return .orange
        case .unavailable: return .red
        case .unknown: return .secondary
        }
    }

    private func directionColor(_ direction: LocalTrend.Direction) -> Color {
        switch direction {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        case .notEnoughData: return .secondary
        }
    }
}

private struct SourceHeader: View {
    let title: String
    let source: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(source).font(.caption2.bold()).textCase(nil)
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
