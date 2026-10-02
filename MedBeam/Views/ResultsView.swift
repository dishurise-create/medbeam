import SwiftUI
import MapKit

struct ResultsView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    /// Where the map is currently looking (updated when the user stops moving it)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var currentCamera: MapCamera?
    /// Center of the map right after results were shown. "Search this area" appears
    /// only when the user moves away from here.
    @State private var resultsCenter: CLLocationCoordinate2D?
    @State private var sheet: ActiveSheet?
    /// Set when the user taps "Call". When they come back to the app, we ask how it went.
    @State private var pendingCall: (pharmacy: Pharmacy, time: Date)?
    @State private var showTrends = false
    /// How far the list panel is pulled up over the map
    @State private var detent: PanelDetent = .medium
    @State private var dragOffset: CGFloat = 0

    /// Most pins shown at once. Zoomed out, only the best-chance pharmacies are shown.
    static let maxPins = 20
    /// Zoom limits, in meters of camera distance. Fully zoomed out shows roughly 60 miles
    /// across on the full-screen map, enough for the widest (25-mile) rural search.
    static let minZoom = 300.0
    static let maxZoom = 400_000.0

    typealias RankedPharmacy = (pharmacy: Pharmacy, estimate: AvailabilityEstimate)

    enum PanelDetent: CaseIterable {
        case collapsed, medium, large

        func height(in total: CGFloat) -> CGFloat {
            switch self {
            case .collapsed: return 116
            case .medium: return max(280, total * 0.46)
            case .large: return max(320, total - 8)
            }
        }
    }

    enum ActiveSheet: Identifiable {
        case detail(Pharmacy)
        case report(Pharmacy)

        var id: String {
            switch self {
            case .detail(let p): return "detail-\(p.id)"
            case .report(let p): return "report-\(p.id)"
            }
        }
    }

    var body: some View {
        let ranked = app.rankedPharmacies
        let pins = visiblePins(ranked)

        GeometryReader { geo in
            let total = geo.size.height
            let height = min(PanelDetent.large.height(in: total),
                             max(PanelDetent.collapsed.height(in: total), detent.height(in: total) - dragOffset))
            // The map keeps its pins, logo and controls clear of the panel (up to the middle position)
            let mapInset = min(height, PanelDetent.medium.height(in: total))

            ZStack(alignment: .bottom) {
                map(pins.shown)
                    .safeAreaPadding(.bottom, mapInset)
                    .safeAreaPadding(.trailing, 56)   // room for the zoom buttons
                    .opacity(app.errorMessage == nil ? 1 : 0.35)
                    .allowsHitTesting(app.errorMessage == nil)

                if app.errorMessage == nil, detent != .large {
                    searchAreaButton(noPinsInView: pins.inView == 0)
                        .padding(.bottom, height + 12)
                }

                panel(ranked, total: total)
                    .frame(height: height)
            }
            .overlay(alignment: .top) { mapBanner(shown: pins.shown.count, total: pins.inView) }
            .overlay(alignment: .topTrailing) { if detent != .large { zoomControls } }
        }
        .navigationTitle(app.selectedMedication?.shortName ?? "Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let medication = app.selectedMedication {
                ToolbarItem(placement: .topBarTrailing) {
                    let saved = app.watchlist.contains(medication)
                    Button { app.toggleWatch(medication) } label: {
                        Label(saved ? "Remove from My medications" : "Save to My medications",
                              systemImage: saved ? "star.fill" : "star")
                            .symbolEffect(.bounce, value: saved)
                    }
                    .tint(saved ? .yellow : nil)
                    .sensoryFeedback(.impact, trigger: saved)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTrends = true } label: {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(app.isLoading || app.shortage == nil)
            }
        }
        .navigationDestination(isPresented: $showTrends) { TrendsView() }
        .task {
            await app.findPharmacies()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "autoOpenTrends") { showTrends = true }
            #endif
        }
        .onChange(of: app.pharmacies.map(\.id)) { _, _ in
            // New results → zoom the map to fit them
            fitAllResults()
        }
        .onAppear { if visibleRegion == nil { fitAllResults() } }
        .sensoryFeedback(.selection, trigger: sheet?.id)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .detail(let pharmacy):
                PharmacyDetailView(pharmacy: pharmacy) {
                    pendingCall = (pharmacy, .now)
                } onReport: {
                    self.sheet = .report(pharmacy)
                }
                .presentationDetents([.medium, .large])
                .tint(settings.accent.color)   // sheets don't inherit the app's tint
            case .report(let pharmacy):
                ReportPromptView(pharmacy: pharmacy)
                    .presentationDetents([.height(380)])
                    .tint(settings.accent.color)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the phone call → ask "Did they have it?"
            guard phase == .active, let call = pendingCall, Date.now.timeIntervalSince(call.time) > 3 else { return }
            pendingCall = nil
            sheet = .report(call.pharmacy)
        }
    }

    // MARK: - Slide-up panel

    private func panel(_ ranked: [RankedPharmacy], total: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelHeader(count: ranked.count)
                .contentShape(Rectangle())
                .gesture(panelDrag(total: total))
                .onTapGesture {
                    // Tapping the header steps the panel up, or back down from full height
                    withAnimation(.spring(duration: 0.35)) {
                        detent = detent == .collapsed ? .medium : (detent == .medium ? .large : .medium)
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Drag or tap to resize the pharmacy list")

            Divider()

            if app.isLoading {
                ProgressView("Checking FDA data and nearby pharmacies…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = app.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load pharmacies", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await app.findPharmacies(force: true) } }
                        .buttonStyle(BrandButtonStyle())
                }
            } else {
                pharmacyList(ranked)
            }
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func panelHeader(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                Text(app.isLoading || app.errorMessage != nil ? "Pharmacies" : "\(count) \(count == 1 ? "pharmacy" : "pharmacies")")
                    .font(.headline)
                    .contentTransition(.numericText())
                if !app.isLoading, app.errorMessage == nil {
                    Text(rangeText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if count > 1 {
                    Label("Best first", systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let shortage = app.shortage, app.errorMessage == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ShortageChip(level: shortage.level)
                        if let risk = app.supplyRisk {
                            Button { showTrends = true } label: { SupplyRiskChip(risk: risk) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Shows the supply risk breakdown")
                        }
                        if app.demoMode { SimulatedBadge() }
                    }
                }
                if app.isRefiningEstimates {
                    Label("Refining percentages with more public data…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    CommunityStatusLine(status: app.reports.communityStatus)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func pharmacyList(_ ranked: [RankedPharmacy]) -> some View {
        List {
            if let warning = app.localTrend.earlyWarning {
                Button { showTrends = true } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Early warning").font(.subheadline.bold())
                            Text(warning).font(.footnote)
                            Text("Detected from community reports, not an official FDA shortage.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            if app.searchRadiusMiles > PharmacySearchService.searchRadii[0] {
                Label("No pharmacies nearby, so the search was widened.", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(Array(ranked.enumerated()), id: \.element.pharmacy.id) { index, item in
                Button { sheet = .detail(item.pharmacy) } label: {
                    PharmacyRow(pharmacy: item.pharmacy, estimate: item.estimate, place: app.placeDetails[item.pharmacy.id])
                }
                .buttonStyle(.plain)
                .modifier(AppearAnimation(index: index))
                .listRowBackground(Color.clear)
            }

            Text(Disclaimer.estimate)
                .font(.caption2).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await app.refreshCommunityReports() }
    }

    private func panelDrag(total: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                // Settle on whichever position is closest to where the drag was heading
                let target = detent.height(in: total) - value.predictedEndTranslation.height
                let nearest = PanelDetent.allCases.min {
                    abs($0.height(in: total) - target) < abs($1.height(in: total) - target)
                } ?? .medium
                withAnimation(.spring(duration: 0.35)) {
                    detent = nearest
                    dragOffset = 0
                }
            }
    }

    // MARK: - Map

    private func map(_ shown: [RankedPharmacy]) -> some View {
        // Small dots when zoomed out, or when many pins would overlap
        let distance = currentCamera?.distance ?? 0
        let compact = (shown.count > 8 && distance > 14_000) || distance > 140_000

        return Map(position: $camera, bounds: MapCameraBounds(minimumDistance: Self.minZoom, maximumDistance: Self.maxZoom)) {
            if let center = app.center {
                Annotation(app.isSearchingArea ? "Search area" : "ZIP \(app.zip)", coordinate: center) {
                    Image(systemName: app.isSearchingArea ? "scope" : "house.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, Brand.navy)
                }
            }
            ForEach(shown, id: \.pharmacy.id) { item in
                Annotation(compact ? "" : item.pharmacy.name, coordinate: item.pharmacy.coordinate) {
                    Button { sheet = .detail(item.pharmacy) } label: {
                        MapPin(estimate: item.estimate, compact: compact)
                    }
                    .modifier(PinDrop())
                    .accessibilityLabel("\(item.pharmacy.name), \(item.estimate.headline), \(item.estimate.confidence.rawValue)")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            currentCamera = context.camera
        }
    }

    /// Pharmacies inside the visible map area, capped at `maxPins` (best chance first).
    private func visiblePins(_ ranked: [RankedPharmacy]) -> (shown: [RankedPharmacy], inView: Int) {
        let inView = ranked.filter { item in
            guard let region = visibleRegion else { return true }
            let c = item.pharmacy.coordinate
            return abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
                && abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
        }
        return (Array(inView.prefix(Self.maxPins)), inView.count)
    }

    @ViewBuilder
    private func mapBanner(shown: Int, total: Int) -> some View {
        if detent == .large {
            EmptyView()
        } else if total > shown {
            MapBanner(text: "Top \(shown) of \(total) · zoom in for more")
        } else if !app.isLoading && !app.pharmacies.isEmpty && total == 0 {
            MapBanner(text: "No pharmacies in this view")
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            MapButton(systemImage: "plus", label: "Zoom in") { zoom(by: 0.5) }
            Divider().frame(width: 30)
            MapButton(systemImage: "minus", label: "Zoom out") { zoom(by: 2) }
            Divider().frame(width: 30)
            MapButton(systemImage: "scope", label: "Show all results") { fitAllResults() }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(10)
    }

    /// Shown after the user moves the map away from the searched area.
    @ViewBuilder
    private func searchAreaButton(noPinsInView: Bool) -> some View {
        if let camera = currentCamera, let center = resultsCenter ?? app.center, let region = visibleRegion, !app.isLoading,
           noPinsInView || movedFar(camera.centerCoordinate, from: center, region: region) {
            Button {
                Task { await app.searchArea(around: camera.centerCoordinate) }
            } label: {
                Label("Search this area", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Brand.buttonGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(radius: 3)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// "Far" = more than 40% of the visible map width (so it scales with zoom), at least 1 km.
    private func movedFar(_ point: CLLocationCoordinate2D, from center: CLLocationCoordinate2D, region: MKCoordinateRegion) -> Bool {
        let moved = CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
        let viewWidth = region.span.longitudeDelta * 111_000 * cos(center.latitude * .pi / 180)
        return moved > max(1_000, viewWidth * 0.4)
    }

    /// Moves the map to a region that contains the search center and every result.
    /// (Setting the region directly avoids a bug where the old visible area hid all new pins.)
    private func fitAllResults() {
        guard let center = app.center else { return }
        let coordinates = app.pharmacies.map(\.coordinate) + [center]
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.02),
                                   longitudeDelta: max((maxLon - minLon) * 1.3, 0.02))
        )
        visibleRegion = region
        resultsCenter = region.center
        withAnimation { camera = .region(region) }
    }

    private func zoom(by factor: Double) {
        guard let current = currentCamera else { return }
        let distance = min(Self.maxZoom, max(Self.minZoom, current.distance * factor))
        withAnimation {
            camera = .camera(MapCamera(centerCoordinate: current.centerCoordinate, distance: distance,
                                       heading: current.heading, pitch: current.pitch))
        }
    }

    /// Uses the real distance of the farthest result. In big cities Apple Maps returns
    /// the closest stores only, so "within 8 miles" would overstate what was searched.
    private var rangeText: String {
        let place = app.isSearchingArea ? "the map area" : app.zip
        let farthest = app.pharmacies.map(\.distanceMiles).max() ?? 0
        let miles = farthest < 1 ? String(format: "%.1f", max(farthest, 0.1)) : "\(Int(farthest.rounded(.up)))"
        return "within \(miles) mi of \(place)"
    }
}

/// List rows slide and fade in, one after another.
private struct AppearAnimation: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

/// Map pins pop in.
private struct PinDrop: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.2, anchor: .bottom)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.4).delay(Double.random(in: 0...0.25))) { shown = true }
            }
    }
}

/// "12 community reports nearby" / "Reports: this iPhone only"
struct CommunityStatusLine: View {
    let status: ReportStore.CommunityStatus

    var body: some View {
        Group {
            switch status {
            case .notConfigured:
                Label("Community sharing not set up. Using this iPhone's reports only", systemImage: "iphone")
            case .syncing:
                Label("Loading community reports…", systemImage: "arrow.triangle.2.circlepath")
            case .connected(let count):
                Label(count == 0 ? "No community reports nearby yet. Be the first!" : "\(count) community report\(count == 1 ? "" : "s") nearby (last 30 days)",
                      systemImage: "person.3.fill")
            case .failed:
                Label("Couldn't reach community reports. Pull down to retry", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct MapBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }
}

private struct MapButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

struct PharmacyRow: View {
    let pharmacy: Pharmacy
    let estimate: AvailabilityEstimate
    let place: PlaceDetails?

    var body: some View {
        HStack(spacing: 12) {
            PharmacyAvatar(name: pharmacy.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(pharmacy.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(pharmacy.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(format: "%.1f mi", pharmacy.distanceMiles))
                    if let rating = place?.rating {
                        Text("·")
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                    if let status = place?.openStatusText {
                        Text("·")
                        Text(status).foregroundStyle(place?.isOpenNow == true ? .green : .red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(estimate.headline)
                    .font(.headline)
                    .foregroundStyle(estimate.tier.color)
                ConfidenceBadge(confidence: estimate.confidence)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MapPin: View {
    let estimate: AvailabilityEstimate
    var compact = false

    var body: some View {
        if compact {
            Circle()
                .fill(estimate.tier.color.gradient)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .padding(8) // bigger tap target
                .contentShape(Circle())
        } else {
            HStack(spacing: 3) {
                Image(systemName: "cross.fill").font(.system(size: 8, weight: .heavy))
                Text(estimate.showsPercentage ? estimate.percentText : estimate.tier.shortLabel)
                    .font(.caption2.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(estimate.tier.color.gradient.opacity(estimate.confidence == .low ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
    }
}
