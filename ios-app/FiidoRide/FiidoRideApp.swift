import SwiftData
import SwiftUI

@main
struct FiidoRideApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var location: LocationTracker
    @State private var recorder: RideRecorder
    @State private var bike: BikeConnection

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Ride.self, RawFrame.self, LocationPoint.self)
        } catch {
            fatalError("Could not open the ride database: \(error)")
        }
        let settings = AppSettings()
        let location = LocationTracker()
        let recorder = RideRecorder(context: container.mainContext, location: location)
        self.container = container
        _settings = State(initialValue: settings)
        _location = State(initialValue: location)
        _recorder = State(initialValue: recorder)
        _bike = State(initialValue: BikeConnection(settings: settings, recorder: recorder, location: location))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(location)
                .environment(recorder)
                .environment(bike)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(LocationTracker.self) private var location

    var body: some View {
        TabView {
            Tab("Ride", systemImage: "gauge.with.dots.needle.67percent") { RideView() }
            Tab("Rides", systemImage: "list.bullet.rectangle.portrait") { RidesView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { location.requestAuthorization() }
    }
}
