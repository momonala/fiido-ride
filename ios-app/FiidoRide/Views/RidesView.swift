import Charts
import CoreLocation
import FiidoKit
import MapKit
import SwiftData
import SwiftUI

struct RidesView: View {
    @Query(sort: \Ride.start, order: .reverse) private var rides: [Ride]
    @SceneStorage("ridesGrouping") private var grouping = RideGroup.Kind.days
    @Environment(\.modelContext) private var context
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if grouping == .rides {
                    ForEach(rides) { ride in
                        let single = RideGroup(kind: .rides, rides: [ride])
                        NavigationLink(value: single) { GroupRow(group: single) }
                            .deleteDisabled(ride.isOpen)
                    }
                    .onDelete { offsets in
                        do {
                            try offsets.map { rides[$0] }.forEach(context.deleteRide)
                        } catch {
                            failure = error.localizedDescription
                        }
                    }
                } else {
                    ForEach(RideGroup.grouping(rides.reversed(), by: grouping)) { group in
                        NavigationLink(value: group) { GroupRow(group: group) }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Group", selection: $grouping) {
                    ForEach(RideGroup.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .overlay {
                if rides.isEmpty {
                    ContentUnavailableView("No rides", systemImage: "bicycle")
                }
            }
            .failureAlert("Delete failed", message: $failure)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RideGroup.self) { RideDetailView(group: $0) }
        }
    }
}

private struct GroupRow: View {
    let group: RideGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.title).font(.headline)
                if group.isOpen {
                    Text("Live").font(.caption.bold()).foregroundStyle(.green)
                }
            }
            HStack(spacing: 14) {
                RowFigure(formatted(group.distanceKm, "km"), icon: "point.topleft.down.to.point.bottomright.curvepath")
                RowFigure(Duration.seconds(group.duration).formatted(.time(pattern: .hourMinute)), icon: "clock")
                RowFigure("\(group.batteryUsed)%", icon: "battery.50percent")
                if group.kind != .rides {
                    RowFigure("\(group.rides.count)", icon: "bicycle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

/// An icon hugging its value, centred on the text.
private struct RowFigure: View {
    let value: String
    let icon: String

    init(_ value: String, icon: String) {
        self.value = value
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(value)
        }
    }
}

private extension RideGroup {
    var title: String {
        switch kind {
        case .rides: start.formatted(.dateTime.weekday().day().month().hour().minute())
        case .days: start.formatted(.dateTime.weekday().day().month())
        case .charges: "\(startsAfterCharge ? "Charged" : "From") \(start.formatted(.dateTime.day().month()))"
        }
    }
}

/// Distance up top, then a labelled row each for speed, elevation, battery and assist.
private struct RideSummary: View {
    let group: RideGroup
    let timeInLevel: [(level: AssistLevel, seconds: Double)]
    let elevations: [Elevation]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(number(group.distanceKm))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("km")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(group.title)
                    Text(subtitle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .monospacedDigit()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    SectionLabel("Speed", icon: "speedometer")
                    Stat("Average", formatted(averageSpeed, "km/h"))
                    Stat("Top", formatted(group.maxSpeedKmh, "km/h"))
                }
                if !elevations.isEmpty {
                    GridRow {
                        SectionLabel("Elevation", icon: "mountain.2")
                        Stat("Climb", formatted(elevations.map(\.climbMeters).reduce(0, +), "m", digits: 0))
                        Stat("Descent", formatted(elevations.map(\.descentMeters).reduce(0, +), "m", digits: 0))
                    }
                }
                GridRow {
                    SectionLabel("Battery", icon: "battery.75percent")
                    Stat("Used", "\(group.batteryUsed)%")
                    Stat("Per km", formatted(group.batteryPerKm, "%"))
                    Stat("Full charge", formatted(group.batteryPerKm.map { 100 / $0 }, "km", digits: 0))
                }
                if group.kind == .rides {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        BatteryBar(start: group.startBattery, end: group.endBattery)
                            .gridCellColumns(Self.statColumns)
                    }
                }
                if !timeInLevel.isEmpty {
                    GridRow {
                        SectionLabel("Assist", icon: "bolt.fill")
                        LevelSplit(timeInLevel: timeInLevel)
                            .gridCellColumns(Self.statColumns)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static let statColumns = 3

    private var subtitle: String {
        let time = Duration.seconds(group.duration).formatted(.time(pattern: .hourMinuteSecond))
        return group.kind == .rides ? time : "\(time) · \(group.rides.count) rides"
    }

    private var averageSpeed: Double? {
        group.duration > 0 ? group.distanceKm / (group.duration / 3600) : nil
    }
}

private struct Stat: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SectionLabel: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Image(systemName: icon)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 28)
            .accessibilityLabel(title)
    }
}

/// Solid up to the battery left at the end, faded over what was used.
private struct BatteryBar: View {
    let start: Int
    let end: Int

    var body: some View {
        let color = Color.battery(end)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.fill.tertiary)
                    Capsule().fill(color.opacity(0.35))
                        .frame(width: width * fraction(max(start, end)))
                    Capsule().fill(color)
                        .frame(width: width * fraction(end))
                }
            }
            .frame(height: 10)
            Text("\(start)% → \(end)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func fraction(_ percent: Int) -> CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }
}

/// Share of time in each assist level as one stacked bar.
private struct LevelSplit: View {
    let timeInLevel: [(level: AssistLevel, seconds: Double)]

    var body: some View {
        let total = timeInLevel.map(\.seconds).reduce(0, +)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(timeInLevel, id: \.level) { slice in
                        Rectangle()
                            .fill(slice.level.color)
                            .frame(width: max(0, (geometry.size.width - 2 * CGFloat(timeInLevel.count - 1)) * slice.seconds / total))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                ForEach(timeInLevel, id: \.level) { slice in
                    HStack(spacing: 5) {
                        Circle().fill(slice.level.color).frame(width: 7, height: 7)
                        Text(slice.level.name)
                        Text(Duration.seconds(slice.seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

private struct SpeedOverTime: View {
    let runs: [(level: AssistLevel?, samples: [RideSample])]
    let thresholdKmh: Double

    var body: some View {
        Chart {
            ForEach(runs.indices, id: \.self) { run in
                ForEach(runs[run].samples) {
                    LineMark(x: .value("Time", $0.time), y: .value("km/h", $0.speedKmh), series: .value("Run", run))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(runs[run].level?.color ?? .gray)
                }
            }
            RuleMark(y: .value("Eco above", thresholdKmh))
                .foregroundStyle(.purple)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXAxisLabel("Time", position: .bottom, alignment: .center)
        .chartYAxisLabel("km/h", position: .trailing, alignment: .center)
        .pinchZoom(xLength: timeSpan(runs.flatMap(\.samples).map(\.time)))
    }
}

private func timeSpan(_ times: [Date]) -> TimeInterval {
    guard let first = times.min(), let last = times.max() else { return 0 }
    return last.timeIntervalSince(first)
}

/// Pinch to zoom the x axis, drag to pan once zoomed, double-tap to reset. Unzoomed, horizontal swipes go to the page view.
private struct PinchZoom: ViewModifier {
    let xLength: Double
    @State private var zoom = 1.0
    @GestureState private var pinch = 1.0

    func body(content: Content) -> some View {
        let scale = Self.clamped(zoom * pinch)
        content
            .chartScrollableAxes(scale > 1 ? .horizontal : [])
            .chartXVisibleDomain(length: max(xLength, Self.smallestLength) / scale)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = Self.clamped(zoom * value.magnification) }
            )
            .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = 1 } }
    }

    private static func clamped(_ scale: Double) -> Double { min(max(scale, 1), maxZoom) }
    private static let maxZoom = 20.0
    private static let smallestLength = 1.0
}

private extension View {
    func pinchZoom(xLength: Double) -> some View { modifier(PinchZoom(xLength: xLength)) }
}

/// Battery % against time, or against distance from the start of the group.
private struct BatteryChart: View {
    let samples: [RideSample]
    let byDistance: Bool

    var body: some View {
        Chart(samples) { sample in
            if byDistance {
                LineMark(x: .value("km", sample.distanceKm), y: .value("%", sample.battery),
                         series: .value("Ride", sample.rideID.uuidString))
            } else {
                LineMark(x: .value("Time", sample.time), y: .value("%", sample.battery),
                         series: .value("Ride", sample.rideID.uuidString))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxisLabel(byDistance ? "km" : "Time", position: .bottom, alignment: .center)
        .chartYAxisLabel("%", position: .trailing, alignment: .center)
        .pinchZoom(xLength: byDistance ? (samples.map(\.distanceKm).max() ?? 0) : timeSpan(samples.map(\.time)))
    }
}

private struct SpeedDensity: View {
    let points: [DensityPoint]
    let thresholdKmh: Double

    var body: some View {
        let levels = AssistLevel.allCases.filter { level in points.contains { $0.level == level } }
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("km/h", point.kmh), y: .value("min per km/h", point.minutesPerKmh), stacking: .unstacked)
                    .foregroundStyle(by: .value("Level", point.level.name))
                    .opacity(0.2)
                LineMark(x: .value("km/h", point.kmh), y: .value("min per km/h", point.minutesPerKmh))
                    .foregroundStyle(by: .value("Level", point.level.name))
            }
            RuleMark(x: .value("Eco above", thresholdKmh))
                .foregroundStyle(.purple)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartForegroundStyleScale(domain: levels.map(\.name), range: levels.map(\.color))
        .chartLegend(.hidden)
        .chartXAxisLabel("km/h", position: .bottom, alignment: .center)
        .chartYAxisLabel("min per km/h", position: .trailing, alignment: .center)
        .pinchZoom(xLength: points.map(\.kmh).max() ?? 0)
    }
}

/// Minutes per km/h moving at one assist level, at one point of a smoothed speed distribution.
private struct DensityPoint: Identifiable {
    let level: AssistLevel
    let kmh: Double
    let minutesPerKmh: Double
    var id: String { "\(level.rawValue)-\(kmh)" }

    static func curves(_ secondsAtSpeed: [AssistLevel: [Double: Double]]) -> [DensityPoint] {
        let top = (secondsAtSpeed.values.flatMap(\.keys).max() ?? 0) + bandwidthKmh * 3
        let grid = stride(from: 0, through: top, by: gridStepKmh).map { $0 }
        return secondsAtSpeed.flatMap { level, seconds in
            zip(grid, Density.curve(weights: seconds, at: grid, bandwidth: bandwidthKmh)).map {
                DensityPoint(level: level, kmh: $0, minutesPerKmh: $1 / 60)
            }
        }
    }

    private static let bandwidthKmh = 1.0
    private static let gridStepKmh = 0.25
}

private struct AltitudeSample: Identifiable {
    let rideID: UUID
    let time: Date
    let meters: Double
    var id: Date { time }
}

private struct RideSample: Identifiable {
    let rideID: UUID
    let time: Date
    let speedKmh: Double
    /// From the start of the first ride in the group.
    let distanceKm: Double
    let battery: Int
    let level: AssistLevel?
    var id: Date { time }
}

struct RideDetailView: View {
    let group: RideGroup
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var samples: [RideSample] = []
    @State private var routes: [[CLLocationCoordinate2D]] = []
    @State private var timeInLevel: [(level: AssistLevel, seconds: Double)] = []
    @State private var elevations: [Elevation] = []
    @State private var altitudes: [AltitudeSample] = []
    @State private var speedDensity: [DensityPoint] = []

    var body: some View {
        List {
            Section {
                RideSummary(group: group, timeInLevel: timeInLevel, elevations: elevations)
            }
            if routes.contains(where: { $0.count > 1 }) {
                Section {
                    Map(interactionModes: [.zoom, .pan]) {
                        ForEach(routes.indices, id: \.self) { index in
                            MapPolyline(coordinates: routes[index]).stroke(.purple, lineWidth: 4)
                        }
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }
            if !samples.isEmpty {
                Section {
                    TabView {
                        SpeedDensity(points: speedDensity, thresholdKmh: settings.thresholdKmh)
                            .padding(.top, Self.chartTopRoom)
                            .padding(.bottom, Self.pageDotsHeight)
                        SpeedOverTime(runs: levelRuns, thresholdKmh: settings.thresholdKmh)
                            .padding(.top, Self.chartTopRoom)
                            .padding(.bottom, Self.pageDotsHeight)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .never))
                    .listRowInsets(Self.pagedChartInsets)
                    .frame(height: 200 + Self.chartTopRoom + Self.pageDotsHeight)
                } header: {
                    Label("Speed", systemImage: "speedometer")
                }
                Section {
                    TabView {
                        BatteryChart(samples: samples, byDistance: true)
                            .padding(.top, Self.chartTopRoom)
                            .padding(.bottom, Self.pageDotsHeight)
                        BatteryChart(samples: samples, byDistance: false)
                            .padding(.top, Self.chartTopRoom)
                            .padding(.bottom, Self.pageDotsHeight)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .never))
                    .listRowInsets(Self.pagedChartInsets)
                    .frame(height: 180 + Self.chartTopRoom + Self.pageDotsHeight)
                } header: {
                    Label("Battery", systemImage: "battery.100percent")
                }
                if !altitudes.isEmpty {
                    Section {
                        Chart(altitudes) {
                            LineMark(x: .value("Time", $0.time), y: .value("m", $0.meters),
                                     series: .value("Ride", $0.rideID.uuidString))
                                .foregroundStyle(.brown)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel("Time", position: .bottom, alignment: .center)
                        .chartYAxisLabel("m", position: .trailing, alignment: .center)
                        .pinchZoom(xLength: timeSpan(altitudes.map(\.time)))
                        .frame(height: 160)
                        .padding(.top, Self.chartTopRoom)
                    } header: {
                    Label("Altitude", systemImage: "mountain.2")
                }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, 4, for: .scrollContent)
        .task(id: group.isOpen) {
            load()
            while group.isOpen, (try? await Task.sleep(for: .seconds(Self.openRideReloadSeconds))) != nil { load() }
        }
    }

    private static let openRideReloadSeconds = 10.0
    private static let longestCountedGapSeconds = 10.0
    private static let maxChartPoints = 1500
    private static let maxGroupChartPoints = 300
    private static let worstHorizontalAccuracyMeters = 20.0
    private static let pageDotsHeight: CGFloat = 34
    private static let pagedChartInsets = EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
    private static let chartTopRoom: CGFloat = 12

    /// Stretches of one ride at one assist level, each sharing its first sample with the previous stretch so the line stays joined.
    private var levelRuns: [(level: AssistLevel?, samples: [RideSample])] {
        var runs: [(level: AssistLevel?, samples: [RideSample])] = []
        var previous: RideSample?
        for sample in samples {
            if let previous, previous.rideID == sample.rideID, previous.level == sample.level {
                runs[runs.count - 1].samples.append(sample)
            } else {
                let joined = previous.flatMap { $0.rideID == sample.rideID ? [$0] : nil } ?? []
                runs.append((sample.level, joined + [sample]))
            }
            previous = sample
        }
        return runs
    }

    private func load() {
        let statsRegister = Int(Poll.stats.rawValue)
        let motorRegister = Int(Poll.motor.rawValue)
        var seconds: [AssistLevel: Double] = [:]
        var secondsAtSpeed: [AssistLevel: [Double: Double]] = [:]
        var all: [RideSample] = []
        var routes: [[CLLocationCoordinate2D]] = []
        var elevations: [Elevation] = []
        var altitudes: [AltitudeSample] = []

        var coveredKm = 0.0
        for ride in group.rides {
            let id = ride.id
            let frames = (try? context.fetch(FetchDescriptor<RawFrame>(
                predicate: #Predicate { $0.rideID == id && ($0.register == statsRegister || $0.register == motorRegister) },
                sortBy: [SortDescriptor(\.time)]
            ))) ?? []
            var battery = ride.startBattery
            let rideSamples = frames.compactMap { frame -> RideSample? in
                let payload = [UInt8](frame.payload)
                if let motor = Motor(payload: payload) {
                    battery = motor.batteryPercent
                    return nil
                }
                return Stats(payload: payload).map {
                    RideSample(rideID: id, time: frame.time, speedKmh: $0.speedKmh,
                               distanceKm: coveredKm + $0.totalKm - ride.startOdometerKm, battery: battery, level: $0.level)
                }
            }
            for (previous, next) in zip(rideSamples, rideSamples.dropFirst()) where previous.speedKmh > 0 {
                let gap = min(next.time.timeIntervalSince(previous.time), Self.longestCountedGapSeconds)
                guard let level = previous.level else { continue }
                seconds[level, default: 0] += gap
                secondsAtSpeed[level, default: [:]][previous.speedKmh, default: 0] += gap
            }
            all += rideSamples
            coveredKm += ride.distanceKm

            let points = (try? context.fetch(FetchDescriptor<LocationPoint>(
                predicate: #Predicate { $0.rideID == id },
                sortBy: [SortDescriptor(\.time)]
            ))) ?? []
            routes.append(points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })

            let accurate = points.filter { $0.horizontalAccuracy <= Self.worstHorizontalAccuracyMeters }
            if accurate.count > 1 {
                let elevation = Elevation(altitudes: accurate.map(\.altitude))
                elevations.append(elevation)
                altitudes += zip(accurate, elevation.smoothed).map { AltitudeSample(rideID: id, time: $0.time, meters: $1) }
            }
        }

        timeInLevel = AssistLevel.allCases.compactMap { level in seconds[level].map { (level, $0) } }
        speedDensity = DensityPoint.curves(secondsAtSpeed)
        let maxPoints = group.kind == .rides ? Self.maxChartPoints : Self.maxGroupChartPoints
        let step = max(1, all.count / maxPoints)
        samples = stride(from: 0, to: all.count, by: step).map { start in
            let window = all[start..<min(start + step, all.count)].filter { $0.rideID == all[start].rideID }
            let middle = window[window.startIndex + window.count / 2]
            return RideSample(rideID: middle.rideID, time: middle.time,
                              speedKmh: window.map(\.speedKmh).reduce(0, +) / Double(window.count),
                              distanceKm: middle.distanceKm, battery: middle.battery, level: middle.level)
        }
        self.routes = routes
        self.elevations = elevations
        let altitudeStep = max(1, altitudes.count / maxPoints)
        self.altitudes = stride(from: 0, to: altitudes.count, by: altitudeStep).map { altitudes[$0] }
    }
}
