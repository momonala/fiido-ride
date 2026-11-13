import FiidoKit
import SwiftData
import SwiftUI
import UIKit

extension Color {
    static let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.53)
    static let neonCyan = Color(red: 0.0, green: 0.78, blue: 1.0)
    static let neonOrange = Color(red: 1.0, green: 0.48, blue: 0.0)
    static let neonPink = Color(red: 1.0, green: 0.1, blue: 0.47)
    static let neonViolet = Color(red: 0.69, green: 0.15, blue: 1.0)
    static let neonYellow = Color(red: 1.0, green: 0.92, blue: 0.0)
    static let neonRed = Color(red: 1.0, green: 0.16, blue: 0.24)
}

extension AssistLevel {
    var color: Color {
        switch self {
        case .off: .gray
        case .eco: .neonGreen
        case .normal: .neonCyan
        case .sport: .neonOrange
        case .turbo: .neonPink
        case .turboPlus: .neonViolet
        }
    }
}

extension BikeConnection.Link {
    var label: String {
        switch self {
        case .bluetoothOff: "Bluetooth off"
        case .searching: "Searching"
        case .connecting: "Connecting"
        case .ready: "Connected"
        case .released: "Disconnected"
        }
    }
}

struct ConnectionIndicator: View {
    @Environment(BikeConnection.self) private var bike
    var color: Color = .primary

    var body: some View {
        let connected = bike.link == .ready
        Image(systemName: connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
            .font(.subheadline)
            .foregroundStyle(connected ? color : .gray)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .symbolEffect(.pulse, isActive: bike.link == .searching || bike.link == .connecting)
            .accessibilityLabel(bike.link.label)
    }
}

struct PowerButton: View {
    @Environment(BikeConnection.self) private var bike
    @State private var confirmingOff = false

    var body: some View {
        let on = bike.stats?.controllerOn == true
        Button {
            if on { confirmingOff = true } else { bike.setPower(true) }
        } label: {
            Image(systemName: "power")
                .overlay {
                    if !on { Image(systemName: "line.diagonal").rotationEffect(.degrees(90)).scaleEffect(1.3) }
                }
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(on ? .white : .gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(!bike.canSwitchPower)
        .accessibilityLabel(on ? "Power off" : "Power on")
        .confirmationDialog("Power off the bike?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Power off", role: .destructive) { bike.setPower(false) }
        }
    }
}

struct ExportButton: View {
    @Environment(\.modelContext) private var context
    @State private var files: ExportedFiles?
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            if busy { ProgressView() } else { Label("Export CSV", systemImage: "square.and.arrow.up") }
        }
        .disabled(busy)
        .sheet(item: $files) { ShareSheet(items: $0.urls) }
        .failureAlert("Export failed", message: $failure)
    }

    private func export() async {
        busy = true
        defer { busy = false }
        do {
            try context.save()
            let urls = try await Exporter(modelContainer: context.container).export()
            files = ExportedFiles(urls: urls)
        } catch {
            failure = error.localizedDescription
        }
    }
}

extension View {
    func failureAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

struct ExportedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

func formatted(_ value: Double?, _ unit: String, digits: Int = 1) -> String {
    guard let value else { return "–" }
    return "\(number(value, digits: digits)) \(unit)"
}

func number(_ value: Double, digits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(.posix))
}

extension Color {
    static func battery(_ percent: Int) -> Color {
        switch percent {
        case 90...: .neonGreen
        case 40...: .neonYellow
        default: .neonRed
        }
    }
}

extension Locale {
    static let posix = Locale(identifier: "en_US_POSIX")
}


extension AutoPower.Status {
    var label: String {
        switch self {
        case .waiting: "Waiting"
        case .armed: "Armed"
        case .leaving: "Leaving"
        case .switchingOff: "Switching off"
        case .away: "Away"
        }
    }
}

/// A value row that opens an inline wheel underneath when tapped, like the date rows in Calendar.
struct WheelRow: View {
    let title: String
    @Binding var selection: Double
    let values: [Double]
    let unit: String
    var digits = 0
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            LabeledContent(title) {
                Text(formatted(selection, unit, digits: digits))
                    .monospacedDigit()
                    .foregroundStyle(expanded ? Color.accentColor : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        if expanded {
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { Text(formatted($0, unit, digits: digits)).tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
    }
}
