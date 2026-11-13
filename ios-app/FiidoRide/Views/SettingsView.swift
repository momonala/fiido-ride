import CoreLocation
import FiidoKit
import MapKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BikeConnection.self) private var bike
    @Environment(LocationTracker.self) private var location
    @Environment(\.modelContext) private var context
    @Query private var rides: [Ride]
    @State private var confirmingDelete = false
    @State private var failure: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Status") {
                        HStack(spacing: 10) {
                            Text(bike.link.label)
                            if bike.link == .released {
                                Button("Connect") { bike.connect() }
                            } else {
                                Button("Disconnect") { bike.release() }
                                    .tint(.red)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let name = bike.bikeName { LabeledContent("Bike", value: name) }
                }

                Section("Power") {
                    Toggle("Auto power by proximity", isOn: $settings.autoPower)
                        .onChange(of: settings.autoPower) { _, on in
                            if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
                        }
                    if settings.autoPower {
                        LabeledContent("State", value: bike.autoPowerStatus?.label ?? "–")
                        WheelRow(title: "On/off at", selection: $settings.autoPowerDbm,
                                 values: stride(from: -40.0, through: -100, by: -1).map { $0 }, unit: "dBm")
                        HomeRow()
                    }
                }

                Section("Auto-Eco") {
                    WheelRow(title: "Eco above", selection: $settings.thresholdKmh,
                             values: stride(from: 10.0, through: 30, by: 1).map { $0 }, unit: "km/h")
                    WheelRow(title: "Normal below", selection: normalBelow,
                             values: stride(from: 5.0, through: settings.thresholdKmh, by: 0.5).map { $0 }, unit: "km/h", digits: 1)
                }

                Section("Bike") {
                    Picker("Speed limit", selection: speedLimit) {
                        ForEach(SpeedLimit.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
                    }
                    .disabled(bike.stats == nil)
                    Toggle("Horn", isOn: flag(\.hornOn, bike.setHorn))
                        .disabled(bike.stats == nil)
                    Toggle("Key sound", isOn: flag(\.keySoundOn, bike.setKeySound))
                        .disabled(bike.stats == nil)
                    Toggle("Light on after dark", isOn: $settings.lightsAfterDark)
                }

                Section("Display") {
                    Toggle("Keep screen on while riding", isOn: $settings.keepScreenOn)
                }

                Section("Recording") {
                    Picker("Poll rate while riding", selection: $settings.ridingPollInterval) {
                        Text("4 per second").tag(0.25)
                        Text("2 per second").tag(0.5)
                        Text("1 per second").tag(1.0)
                    }
                    if location.authorization != .authorizedAlways {
                        Button("Allow location “Always”") {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                    Toggle("Discovery mode", isOn: $settings.discoveryMode)
                }

                Section("Data") {
                    if let sync = MacSync.configured { SyncButton(sync: sync) }
                    ExportButton()
                        .labelStyle(.titleOnly)
                    Button("Delete all rides", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete all rides?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete all rides", role: .destructive, action: deleteAll)
                        }
                }

                Section("Odometer") {
                    OdometerCard(displayKm: bike.stats?.totalKm)
                }

                Section("Hardware") {
                    if let serial = Bundle.main.object(forInfoDictionaryKey: "FiidoBikeSerial") as? String, !serial.isEmpty {
                        LabeledContent("Serial", value: serial)
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = serial }
                            }
                    }
                    LabeledContent("Display", value: version(.meter))
                    LabeledContent("Controller", value: version(.controller))
                    LabeledContent("Battery", value: version(.battery))
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    Link("Protocol reference", destination: URL(string: "https://github.com/dzikus/esphome-fiido-bms")!)
                }
            }
            .failureAlert("Delete failed", message: $failure)
            .navigationTitle("Settings")
        }
    }

    private var normalBelow: Binding<Double> {
        Binding {
            settings.thresholdKmh - settings.hysteresisKmh
        } set: {
            settings.hysteresisKmh = settings.thresholdKmh - $0
        }
    }

    private var speedLimit: Binding<SpeedLimit?> {
        Binding { bike.speedLimit } set: { $0.map(bike.setSpeedLimit) }
    }

    private func flag(_ key: KeyPath<Stats, Bool>, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding { bike.stats?[keyPath: key] ?? false } set: { set($0) }
    }


    private func version(_ poll: Poll) -> String {
        bike.firmware[poll].map { "HW \($0.hardware) · SW \($0.software)" } ?? "–"
    }

    private func deleteAll() {
        do {
            try rides.filter { !$0.isOpen }.forEach(context.deleteRide)
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Bike total split two ways: previous owner vs mine, and old display vs the current one.
private struct OdometerCard: View {
    @Environment(AppSettings.self) private var settings
    let displayKm: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mine").font(.caption).foregroundStyle(.secondary)
                    Text(formatted(displayKm.map { settings.myKm(displayKm: $0) }, "km"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Bike total").font(.caption).foregroundStyle(.secondary)
                    Text(formatted(displayKm.map { settings.bikeTotalKm(displayKm: $0) }, "km"))
                        .font(.title3.weight(.semibold))
                }
            }
            .monospacedDigit()

            if let displayKm {
                SplitBar(title: "Owner",
                         first: ("Before me", AppSettings.purchaseOdometerKm, Color.secondary.opacity(0.4)),
                         second: ("Mine", settings.myKm(displayKm: displayKm), Color.accentColor))
                SplitBar(title: "Display",
                         first: ("Old", AppSettings.oldDisplayAtSwapKm, Color.secondary.opacity(0.4)),
                         second: ("Current", displayKm, Color.neonGreen))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SplitBar: View {
    let title: String
    let first: (name: String, km: Double, color: Color)
    let second: (name: String, km: Double, color: Color)

    var body: some View {
        let share = first.km / max(first.km + second.km, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(first.color).frame(width: (geometry.size.width - 2) * share)
                    Rectangle().fill(second.color)
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            HStack {
                legend(first)
                Spacer()
                legend(second)
            }
            .font(.caption)
            .monospacedDigit()
        }
    }

    private func legend(_ part: (name: String, km: Double, color: Color)) -> some View {
        HStack(spacing: 4) {
            Text(part.name).foregroundStyle(.secondary)
            Text(formatted(part.km, "km")).fontWeight(.semibold)
        }
    }
}

/// Where auto power never switches the bike on.
private struct HomeRow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LocationTracker.self) private var location
    @State private var locating = false
    @State private var failure: String?

    var body: some View {
        if let home = settings.home {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: home, distance: AppSettings.homeRadiusMeters * 8)),
                interactionModes: []) {
                MapCircle(center: home, radius: AppSettings.homeRadiusMeters)
                    .foregroundStyle(.purple.opacity(0.25))
                    .stroke(.purple, lineWidth: 2)
                Marker("Home", systemImage: "house.fill", coordinate: home)
                    .tint(.purple)
            }
            .id("\(home.latitude),\(home.longitude)")
            .frame(height: 140)
            .listRowInsets(EdgeInsets())
        }
        Button {
            Task { await setHome() }
        } label: {
            LabeledContent(settings.home == nil ? "Set home here" : "Move home here") {
                if locating { ProgressView() }
            }
        }
        .disabled(locating)
        .failureAlert("Location unavailable", message: $failure)
        if settings.home != nil {
            Button("Clear home", role: .destructive) { settings.home = nil }
        }
    }

    private func setHome() async {
        locating = true
        defer { locating = false }
        if let fix = await location.currentLocation() {
            settings.home = fix.coordinate
        } else {
            failure = "No GPS fix."
        }
    }
}

private struct SyncButton: View {
    let sync: MacSync
    @State private var started: Date?
    @State private var step: MacSync.Step?
    @State private var lastSynced: Date?
    @State private var failure: String?

    var body: some View {
        Button {
            Task { await run() }
        } label: {
            LabeledContent("Sync to Mac") {
                if started == nil, let lastSynced {
                    Text(lastSynced, format: .dateTime.hour().minute())
                }
            }
        }
        .disabled(started != nil)
        .failureAlert("Sync failed", message: $failure)
        if let started {
            TimelineView(.periodic(from: started, by: 1)) { context in
                SyncProgress(step: step, elapsed: context.date.timeIntervalSince(started))
            }
        }
    }

    private func run() async {
        started = .now
        step = nil
        defer { started = nil }
        do {
            try await sync.run { step = $0 }
            lastSynced = .now
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// tqdm-style line: `██████░░░░░░  3/6  Copying index  4s`.
private struct SyncProgress: View {
    let step: MacSync.Step?
    let elapsed: TimeInterval
    private static let width = 16

    var body: some View {
        let done = step.map { $0.number - 1 } ?? 0
        let total = step?.total ?? 1
        let filled = Self.width * done / max(total, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(repeating: "█", count: filled) + String(repeating: "░", count: Self.width - filled))
                    .foregroundStyle(Color.accentColor)
                Text("\(step?.number ?? 0)/\(step?.total ?? 0)")
                Spacer()
                Text("\(Int(elapsed))s")
                    .foregroundStyle(.secondary)
            }
            Text(step?.label ?? "Connecting")
                .foregroundStyle(.secondary)
        }
        .font(.footnote.monospaced())
        .monospacedDigit()
    }
}
