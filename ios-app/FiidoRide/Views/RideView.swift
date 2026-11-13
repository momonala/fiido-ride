import Combine
import CoreLocation
import Charts
import FiidoKit
import SwiftData
import SwiftUI
import UIKit

struct RideView: View {
    @Environment(BikeConnection.self) private var bike
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HUDView()
            .statusBarHidden()
            .task(id: keepAwake) { UIApplication.shared.isIdleTimerDisabled = keepAwake }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var keepAwake: Bool {
        settings.keepScreenOn && bike.stats?.controllerOn == true
    }
}

private struct HUDView: View {
    @Environment(BikeConnection.self) private var bike
    @State private var topSafeArea: CGFloat = 0
    @State private var boosts = 0
    private static let columnNudge: CGFloat = 3
    private static let unitGap: CGFloat = 6

    var body: some View {
        let stats = bike.stats
        let tint = bike.displayedLevel?.color ?? .gray
        let liveBattery = bike.motor?.batteryPercent
        let battery = liveBattery ?? bike.lastBatteryPercent

        VStack(spacing: 12) {
            VStack(spacing: 12) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 58, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                    StatusColumn(battery: battery)
                        .offset(x: Self.columnNudge)
                }
                .padding(.top, 12)

                Spacer()
                VStack(spacing: 0) {
                    Text(stats.map { String(Int($0.speedKmh.rounded())) } ?? "–")
                        .font(.system(size: 150, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: stats?.speedKmh ?? 0))
                        .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                            Text("km/h")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .alignmentGuide(.trailing) { $0[.leading] - Self.unitGap }
                        }
                    BikeBattery(percent: battery, live: liveBattery != nil)
                        .padding(.top, 14)
                }
                .padding(.top, 24)
                Spacer()

                SpeedTrace(points: bike.trace.points, window: bike.trace.window)
                    .frame(height: 144)
            }
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                if bike.boost() { boosts += 1 }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: boosts)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    AssistWheel()
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                    LightTile()
                        .frame(width: 104)
                }
                .frame(height: 104)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) { topSafeArea = $0 }
        .overlay(alignment: .top) { CornerControls(screenCornerRadius: topSafeArea).ignoresSafeArea() }
        .background {
            LinearGradient(colors: [tint.opacity(0.75), tint.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .animation(.smooth, value: stats?.speedKmh)
        .animation(.smooth, value: bike.displayedLevel)
    }
}

/// iOS doesn't publish the corner radius; the top safe-area inset tracks it closely (47 pt against 47.33 pt on an iPhone 13).
private struct CornerControls: View {
    let screenCornerRadius: CGFloat
    private static let controlSize: CGFloat = 55
    private static let nudge: CGFloat = 8
    private static let powerNudge: CGFloat = 6

    private var inset: CGFloat {
        let radius = Self.controlSize / 2
        return max(0, screenCornerRadius - (screenCornerRadius - radius) / 2.squareRoot() - radius) + Self.nudge
    }

    var body: some View {
        PowerButton()
            .frame(width: Self.controlSize, height: Self.controlSize)
            .padding([.leading, .top], Self.powerNudge)
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Its last row sits on the clock's baseline.
private struct StatusColumn: View {
    let battery: Int?
    private static let width: CGFloat = 77
    private static let rowGap: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            BluetoothBadge()
            PhoneBatteryBadge()
            WeatherBadge()
            TimelineView(.everyMinute) { context in
                DistanceBadge(startOfToday: Calendar.current.startOfDay(for: context.date))
            }
            RangeBadge(battery: battery)
        }
        .frame(width: Self.width, alignment: .leading)
    }
}

private struct SpeedTrace: View {
    let points: [TracePoint]
    let window: TimeInterval

    var body: some View {
        let end = points.last?.time ?? .now
        Chart(points) { point in
            LineMark(x: .value("Time", point.time), y: .value("Speed", point.speedKmh))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(.primary)
        }
        .chartXScale(domain: end.addingTimeInterval(-window)...end)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct BikeBattery: View {
    let percent: Int?
    let live: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(percent.map { "\($0)%" } ?? "–")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percent ?? 0)))
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(live ? percent.map { Color.battery($0) } ?? .secondary : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var symbol: String {
        switch percent ?? 0 {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}

private struct WeatherBadge: View {
    @Environment(LocationTracker.self) private var location
    @State private var weather: Weather?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: weather?.symbol ?? "cloud")
                .symbolRenderingMode(.multicolor)
                .hudIcon()
            Text(label)
        }
        .hudBadge()
        .task { await keepFresh() }
    }

    private var label: String {
        guard let weather else { return "–" }
        let temperature = "\(Int(weather.temperatureC.rounded()))°"
        return weather.rainChancePercent.map { "\(temperature) · \($0)%" } ?? temperature
    }

    private func keepFresh() async {
        while !Task.isCancelled {
            var place = location.lastKnown
            if place.map({ -$0.timestamp.timeIntervalSinceNow > Self.refreshSeconds }) ?? true {
                place = await freshLocation() ?? place
            }
            if let place {
                weather = await Self.fetch(place.coordinate) ?? weather
            }
            try? await Task.sleep(for: .seconds(weather == nil ? Self.retrySeconds : Self.refreshSeconds))
        }
    }

    private func freshLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await location.currentLocation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.locationTimeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func fetch(_ place: CLLocationCoordinate2D) async -> Weather? {
        var request = URLRequest(url: Weather.url(latitude: place.latitude, longitude: place.longitude))
        request.timeoutInterval = requestTimeoutSeconds
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? Weather(json: data)
    }

    private static let refreshSeconds = 15.0 * 60
    private static let retrySeconds = 60.0
    private static let requestTimeoutSeconds = 10.0
    private static let locationTimeoutSeconds = 10.0
}

private struct DistanceBadge: View {
    @Environment(RideRecorder.self) private var recorder
    @Query private var todaysRides: [Ride]

    init(startOfToday: Date) {
        _todaysRides = Query(filter: #Predicate<Ride> { $0.start >= startOfToday })
    }

    var body: some View {
        let current = recorder.currentRide
        let trip = current?.distanceKm ?? 0
        let today = todaysRides.filter { $0.id != current?.id }.map(\.distanceKm).reduce(0, +) + trip
        HStack(spacing: 4) {
            NoIcon()
            Text("\(number(trip, digits: 0)) · \(formatted(today, "km", digits: 0))")
        }
        .hudBadge()
    }
}

/// Km left on the battery, then the total this charge should give.
private struct RangeBadge: View {
    let battery: Int?
    @Query(Self.recentRides) private var newestFirst: [Ride]

    private static var recentRides: FetchDescriptor<Ride> {
        var descriptor = FetchDescriptor<Ride>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 100
        return descriptor
    }

    var body: some View {
        let charges = RideGroup.grouping(newestFirst.reversed(), by: .charges)
        let range = battery.flatMap { RideGroup.chargeRange(charges, battery: $0) }
        HStack(spacing: 4) {
            NoIcon()
            Text(range.map { "\(number($0.leftKm, digits: 0)) · \(formatted($0.chargeKm, "km", digits: 0))" } ?? "–")
        }
        .hudBadge()
    }
}

private struct NoIcon: View {
    var body: some View {
        Image(systemName: "circle").hudIcon().hidden()
    }
}

private struct BluetoothBadge: View {
    @Environment(BikeConnection.self) private var bike

    var body: some View {
        HStack(spacing: 4) {
            ConnectionIndicator(color: .white)
                .hudIcon()
            Text(formatted(bike.signalDbm, "dBm", digits: 0))
        }
        .hudBadge()
    }
}

private extension View {
    func hudIcon() -> some View {
        font(.subheadline).frame(width: 18)
    }

    func hudBadge() -> some View {
        fixedSize()
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 2)
    }
}

private struct PhoneBatteryBadge: View {
    @State private var level = UIDevice.current.batteryLevel
    @State private var state = UIDevice.current.batteryState

    var body: some View {
        let charging = state == .charging || state == .full
        HStack(spacing: 4) {
            Image(systemName: charging ? "bolt.fill" : "iphone")
                .hudIcon()
            Text(level >= 0 ? "\(Int((level * 100).rounded()))%" : "–")
        }
        .foregroundStyle(charging ? .neonGreen : .white)
        .hudBadge()
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refresh() }
    }

    private func refresh() {
        level = UIDevice.current.batteryLevel
        state = UIDevice.current.batteryState
    }
}

private struct LightTile: View {
    @Environment(BikeConnection.self) private var bike

    var body: some View {
        let on = bike.displayedLight == true
        Button {
            bike.toggleLight()
        } label: {
            Image(systemName: on ? "headlight.low.beam.fill" : "headlight.low.beam")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(on ? .white : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(.white.opacity(0.35)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 28))
        .disabled(bike.stats?.controllerOn != true)
        .sensoryFeedback(.impact, trigger: on)
    }
}

private struct AssistWheel: View {
    private enum Choice: Hashable {
        case auto
        case level(AssistLevel)
    }

    private static let selectedRowHalfHeight: CGFloat = 22

    @Environment(BikeConnection.self) private var bike
    @Environment(AppSettings.self) private var settings
    @State private var height: CGFloat = 0

    var body: some View {
        Picker("Assist", selection: selection) {
            Text("Auto").tag(Choice.auto)
            ForEach(AssistLevel.allCases, id: \.self) { level in
                Text(level.name).tag(Choice.level(level))
            }
        }
        .pickerStyle(.wheel)
        .font(.largeTitle.weight(.bold))
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            if !settings.autoAssist, abs(tap.location.y - height / 2) <= Self.selectedRowHalfHeight { bike.selectAuto() }
        })
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .sensoryFeedback(.selection, trigger: settings.autoAssist)
    }

    private var selection: Binding<Choice> {
        Binding {
            settings.autoAssist ? .auto : .level(bike.displayedLevel ?? .off)
        } set: { choice in
            switch choice {
            case .auto: bike.selectAuto()
            case .level(let level): bike.select(level)
            }
        }
    }
}
