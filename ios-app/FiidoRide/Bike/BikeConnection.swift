@preconcurrency import CoreBluetooth
import FiidoKit
import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class BikeConnection: NSObject {
    enum Link: Equatable {
        case bluetoothOff, searching, connecting, ready, released
    }

    private(set) var link: Link = .searching
    private(set) var bikeName: String?
    private(set) var stats: Stats?
    private(set) var motor: Motor?
    private(set) var lastBatteryPercent = UserDefaults.standard.object(forKey: BikeConnection.batteryKey) as? Int
    private(set) var speedLimit: SpeedLimit?
    private(set) var trace = RollingTrace()
    private(set) var signalDbm: Double?
    private(set) var firmware: [Poll: FirmwareVersion] = [:]
    private var requested: (level: AssistLevel, at: Date)?
    private var requestedLight: (on: Bool, at: Date)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let recorder: RideRecorder
    @ObservationIgnored private let location: LocationTracker
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    /// Exists exactly while notifications are on and polling runs, i.e. while `link == .ready`.
    private struct Session {
        let tx: CBCharacteristic
        var assembler = FrameAssembler()
        var pollTask: Task<Void, Never>?
        var lastStatsAt = Date()
        var unansweredPolls = 0
    }

    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var autoEco: AutoEco
    private var autoPower: AutoPower
    @ObservationIgnored private var discoveryIndex = 0

    private static let advertisedService = CBUUID(string: "C3E60203-E966-1000-8000-BE99C223DF6A")
    private static let service = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0DFFE0")
    private static let rxCharacteristic = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0DFFE1")
    private static let txCharacteristic = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0DFFE2")
    private static let bikeKey = "bikeIdentifier"
    private static let batteryKey = "lastBatteryPercent"
    private static let idlePollInterval: TimeInterval = 5
    private static let awayPollInterval: TimeInterval = 1
    private static let silenceBeforeReconnect: TimeInterval = 15
    private static let unansweredPollsBeforeReconnect = 3
    private static let requestDisplayTime: TimeInterval = 3

    init(settings: AppSettings, recorder: RideRecorder, location: LocationTracker) {
        self.settings = settings
        self.recorder = recorder
        self.location = location
        autoEco = AutoEco(config: settings.autoEcoConfig)
        autoPower = AutoPower()
        super.init()
        UNUserNotificationCenter.current().delegate = self
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "fiido-ride"]
        )
    }


    /// The level just picked on the wheel until the bike has had time to confirm it, then the bike's own.
    var displayedLevel: AssistLevel? {
        if let requested, Date().timeIntervalSince(requested.at) < Self.requestDisplayTime { return requested.level }
        return stats?.level
    }

    func select(_ level: AssistLevel) {
        settings.autoAssist = false
        requested = (level, Date())
        send(level.writeFrame)
    }

    var displayedLight: Bool? {
        if let requestedLight, Date().timeIntervalSince(requestedLight.at) < Self.requestDisplayTime {
            return requestedLight.on
        }
        return stats?.lightOn
    }

    func toggleLight() {
        guard let stats, stats.controllerOn, let current = displayedLight else { return }
        requestedLight = (!current, Date())
        send(stats.lightWriteFrame(on: !current))
    }

    func setHorn(_ on: Bool) {
        guard let stats else { return }
        send(stats.hornWriteFrame(on: on))
        refreshSoon()
    }

    var canSwitchPower: Bool {
        guard let stats else { return false }
        return !stats.controllerOn || stats.speedKmh == 0
    }

    func setPower(_ on: Bool) {
        guard let stats, canSwitchPower else { return }
        send(stats.powerWriteFrame(on: on))
        refreshSoon()
    }

    func setKeySound(_ on: Bool) {
        guard let stats else { return }
        send(stats.keySoundWriteFrame(on: on))
        refreshSoon()
    }

    func setSpeedLimit(_ limit: SpeedLimit) {
        guard let stats else { return }
        let write = stats.speedLimitWrite(limit)
        write.first.forEach(send)
        Task { [weak self] in
            if write.delayThen { try? await Task.sleep(for: .milliseconds(50)) }
            write.then.forEach { self?.send($0) }
            self?.refreshSoon()
        }
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.send(Frame.poll(.stats))
            self?.send(Frame.poll(.speedLimit))
        }
    }

    /// Only in Auto with the bike on: Normal for a few seconds, then back to the speed rule. True when a boost started.
    func boost() -> Bool {
        guard settings.autoAssist, link == .ready, stats?.controllerOn == true else { return false }
        if case .write(let level)? = autoEco.boost(at: Date()) {
            requested = (level, Date())
            send(level.writeFrame)
        }
        return autoEco.isBoosting
    }

    func selectAuto() {
        requested = nil
        autoEco = AutoEco(config: settings.autoEcoConfig)
        settings.autoAssist = true
    }

    func connect() {
        link = .searching
        connectKnownOrScan()
    }

    func release() {
        link = .released
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    private func connectKnownOrScan() {
        guard central.state == .poweredOn, link != .released else { return }
        if peripheral == nil,
           let saved = UserDefaults.standard.string(forKey: Self.bikeKey).flatMap(UUID.init(uuidString:)) {
            peripheral = central.retrievePeripherals(withIdentifiers: [saved]).first
        }
        if let peripheral {
            attach(peripheral)
            if peripheral.state == .connected {
                peripheral.discoverServices([Self.service])
            } else {
                link = .connecting
                central.connect(peripheral)
            }
        } else {
            link = .searching
            central.scanForPeripherals(withServices: [Self.advertisedService])
        }
    }

    private func attach(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        bikeName = peripheral.name
    }

    private func linkDropped() {
        endSession()
        guard link != .released, let peripheral else { return }
        link = .connecting
        central.connect(peripheral)
    }

    private func endSession() {
        session?.pollTask?.cancel()
        session = nil
        signalDbm = nil
        stats = nil
        motor = nil
        trace.clear()
        recorder.closeRideIfBikeStaysSilent()
    }

    private func startSession(tx: CBCharacteristic) {
        session?.pollTask?.cancel()
        session = Session(tx: tx)
        link = .ready
        send(Frame.poll(.handshake))
        session?.pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                session?.unansweredPolls += 1
                let riding = stats?.controllerOn == true
                send(Frame.poll(.stats))
                send(Frame.poll(.energy))
                if !riding || tick.isMultiple(of: 2) {
                    [Poll.motor, .battery, .controller, .meter, .speedLimit].forEach { self.send(Frame.poll($0)) }
                }
                peripheral?.readRSSI()
                if settings.discoveryMode {
                    send(Discovery.frame(Discovery.blocks[discoveryIndex % Discovery.blocks.count]))
                    discoveryIndex += 1
                }
                tick += 1

                let watchingForReturn = settings.autoPower && autoPower.status == .away
                let interval = riding ? settings.ridingPollInterval
                    : watchingForReturn ? Self.awayPollInterval : Self.idlePollInterval
                try? await Task.sleep(for: .seconds(interval))
                if let session, let peripheral,
                   session.unansweredPolls >= Self.unansweredPollsBeforeReconnect,
                   Date().timeIntervalSince(session.lastStatsAt) > Self.silenceBeforeReconnect {
                    central.cancelPeripheralConnection(peripheral)
                    return
                }
            }
        }
    }

    private func send(_ frame: Data) {
        guard let peripheral, let session else { return }
        peripheral.writeValue(frame, for: session.tx, type: .withoutResponse)
    }

    private func handle(_ data: Data) {
        let now = Date()
        guard let notifies = session?.assembler.feed(data) else { return }
        for notify in notifies {
            recorder.record(notify, at: now)
            guard let poll = Poll(register: notify.register, payloadLength: notify.payload.count) else { continue }
            switch poll {
            case .stats: Stats(payload: notify.payload).map { handle($0, at: now) }
            case .motor:
                motor = Motor(payload: notify.payload) ?? motor
                if let percent = motor?.batteryPercent, percent != lastBatteryPercent {
                    lastBatteryPercent = percent
                    UserDefaults.standard.set(percent, forKey: Self.batteryKey)
                }
            case .speedLimit:
                if let value = notify.payload.first, let flag = stats?.speedLimitOn,
                   let limit = SpeedLimit(value: value, flagOn: flag) {
                    speedLimit = limit
                }
            case .meter, .battery, .controller: firmware[poll] = FirmwareVersion(payload: notify.payload) ?? firmware[poll]
            case .handshake, .energy: break
            }
        }
    }

    private func handle(_ stats: Stats, at time: Date) {
        session?.lastStatsAt = time
        session?.unansweredPolls = 0
        let switchedOn = self.stats?.controllerOn == false && stats.controllerOn
        self.stats = stats
        if switchedOn { lightUpIfDark(stats, at: time) }
        runAutoPower(stats, at: time)
        trace.append(speedKmh: stats.speedKmh, at: time)
        if let requested, time.timeIntervalSince(requested.at) >= Self.requestDisplayTime { self.requested = nil }
        if let requestedLight, time.timeIntervalSince(requestedLight.at) >= Self.requestDisplayTime {
            self.requestedLight = nil
        }
        guard settings.autoAssist else { return }
        autoEco.config = settings.autoEcoConfig
        switch autoEco.update(stats, at: time) {
        case .write(let level): send(level.writeFrame)
        case .handBack: settings.autoAssist = false
        case nil: break
        }
    }

    var autoPowerStatus: AutoPower.Status? { settings.autoPower && link == .ready ? autoPower.status : nil }

    private func runAutoPower(_ stats: Stats, at time: Date) {
        guard settings.autoPower else {
            autoPower.reset()
            return
        }
        autoPower.config.thresholdRssi = settings.autoPowerDbm
        let wasSwitchingOff = if case .switchingOff = autoPower.status { true } else { false }
        let atHome = settings.home.map { location.isNear($0, within: AppSettings.homeRadiusMeters) } ?? false
        let action = autoPower.update(stats, at: time, mayPowerOn: !atHome)
        if wasSwitchingOff, autoPower.status == .away { notify("\(bikeName ?? "Bike") switched off") }
        let signal = autoPower.rssi.map { formatted($0, "dBm", digits: 0) } ?? "–"
        switch action {
        case .powerOn:
            notify("Switching on", "Signal \(signal)")
            setPower(true)
        case .powerOff:
            notify(wasSwitchingOff ? "Retrying switch-off" : "Switching off", "Signal \(signal)")
            setPower(false)
        case .gaveUp:
            notify("\(bikeName ?? "Bike") didn't switch off")
        case nil:
            break
        }
    }

    private func lightUpIfDark(_ stats: Stats, at time: Date) {
        guard settings.lightsAfterDark, !stats.lightOn, let place = location.lastKnown?.coordinate,
              Sun.isDown(at: time, latitude: place.latitude, longitude: place.longitude) else { return }
        requestedLight = (true, time)
        send(stats.lightWriteFrame(on: true))
    }

    private func notify(_ title: String, _ body: String = "") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension BikeConnection: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if link == .bluetoothOff { link = .searching }
                connectKnownOrScan()
            } else {
                endSession()
                if link != .released { link = .bluetoothOff }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        nonisolated(unsafe) let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first
        MainActor.assumeIsolated {
            restored.map(attach)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            central.stopScan()
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.bikeKey)
            attach(peripheral)
            link = .connecting
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            bikeName = peripheral.name
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated { linkDropped() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: (any Error)?) {
        let droppedOutOfRange = error != nil
        MainActor.assumeIsolated {
            if droppedOutOfRange { autoPower.linkLost(at: Date()) }
            linkDropped()
        }
    }
}

extension BikeConnection: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

extension BikeConnection: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.discoverCharacteristics([Self.rxCharacteristic, Self.txCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: (any Error)?) {
        MainActor.assumeIsolated {
            guard let rx = service.characteristics?.first(where: { $0.uuid == Self.rxCharacteristic }) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.setNotifyValue(true, for: rx)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: (any Error)?) {
        MainActor.assumeIsolated {
            let tx = characteristic.service?.characteristics?.first { $0.uuid == Self.txCharacteristic }
            guard characteristic.isNotifying, let tx else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            startSession(tx: tx)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {
        let value = RSSI.doubleValue
        MainActor.assumeIsolated {
            guard error == nil, value < 0 else { return }
            signalDbm = value
            autoPower.record(rssi: value)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: (any Error)?) {
        MainActor.assumeIsolated {
            if let value = characteristic.value { handle(value) }
        }
    }
}
