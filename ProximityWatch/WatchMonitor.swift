import AppKit
import CoreBluetooth
import Foundation

/// One Apple device seen while you're choosing your watch.
struct NearbyDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

/// Where the app is in its arm-then-lock cycle.
enum MonitorState: Equatable {
    case paused
    case bluetoothOff
    case noWatchChosen
    /// Not armed. The watch hasn't been near while you were using the Mac.
    case waitingForWatch
    /// The watch was near while you were using the Mac. It will lock if the watch leaves.
    case armed
    /// The watch looks gone. Locks once this has lasted `lockDelay` seconds.
    case leaving(since: Date)

    var symbolName: String {
        switch self {
        case .paused: "lock.slash"
        case .bluetoothOff: "antenna.radiowaves.left.and.right.slash"
        case .noWatchChosen: "applewatch.slash"
        case .waitingForWatch: "applewatch"
        case .armed: "applewatch.radiowaves.left.and.right"
        case .leaving: "lock.trianglebadge.exclamationmark"
        }
    }

    var summary: String {
        switch self {
        case .paused: "Paused. Your Mac won't lock on its own."
        case .bluetoothOff: "Bluetooth is off or not allowed for this app. Check System Settings."
        case .noWatchChosen: "Choose your watch to get started."
        case .waitingForWatch: "Not armed yet. It arms once your watch is near while you're using the Mac."
        case .armed: "Armed. Your Mac locks when your watch walks away."
        case .leaving: "Your watch is leaving. Locking soon."
        }
    }
}

/// Watches the Bluetooth signal from your Apple Watch and locks the Mac when it walks away.
///
/// The rule: it only arms after it has seen the watch nearby while you were using the Mac.
/// If you sit down without your watch, nothing ever arms and it never locks you out.
final class WatchMonitor: NSObject, ObservableObject {
    @Published private(set) var state: MonitorState = .noWatchChosen
    @Published private(set) var rssi: Int?
    @Published private(set) var watchName: String?
    @Published private(set) var nearbyDevices: [NearbyDevice] = []
    @Published private(set) var isPicking = false

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled); evaluate() }
    }
    /// Signal strength in dB. Weaker than this counts as "walked away." -75 is a few meters.
    @Published var lockThreshold: Double {
        didSet { defaults.set(lockThreshold, forKey: Keys.lockThreshold) }
    }
    /// Seconds the watch has to stay away before the Mac locks.
    @Published var lockDelay: Double {
        didSet { defaults.set(lockDelay, forKey: Keys.lockDelay) }
    }

    private enum Keys {
        static let enabled = "enabled"
        static let lockThreshold = "lockThreshold"
        static let lockDelay = "lockDelay"
        static let watchID = "watchID"
        static let watchName = "watchName"
    }

    /// To arm, the watch must be this many dB stronger than the lock threshold.
    /// The gap keeps it from flipping between armed and leaving at the edge.
    private let armMargin = 5.0
    /// No reading for this long counts as away, whatever the last reading was.
    private let noSignalTimeout: TimeInterval = 20
    /// Keyboard or mouse input within this window means you're using the Mac.
    private let activeWindow: TimeInterval = 30

    private let defaults = UserDefaults.standard
    private var central: CBCentralManager!
    private var watch: CBPeripheral?
    private var watchID: UUID?
    private var readings: [Int] = []
    private var lastSeen: Date?
    private var screenLocked = false
    private var timer: Timer?

    override init() {
        defaults.register(defaults: [Keys.enabled: true, Keys.lockThreshold: -75.0, Keys.lockDelay: 10.0])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        lockThreshold = defaults.double(forKey: Keys.lockThreshold)
        lockDelay = defaults.double(forKey: Keys.lockDelay)
        watchID = defaults.string(forKey: Keys.watchID).flatMap(UUID.init(uuidString:))
        watchName = defaults.string(forKey: Keys.watchName)
        super.init()

        central = CBCentralManager(delegate: self, queue: .main)
        observeScreenLock()
        // .common mode keeps the timer firing while a menu or slider is being tracked.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Choosing a watch

    func startPicking() {
        nearbyDevices = []
        isPicking = true
    }

    func stopPicking() {
        isPicking = false
        nearbyDevices = []
    }

    func choose(_ device: NearbyDevice) {
        if let watch { central.cancelPeripheralConnection(watch) }
        watch = nil
        watchID = device.id
        watchName = device.name
        defaults.set(device.id.uuidString, forKey: Keys.watchID)
        defaults.set(device.name, forKey: Keys.watchName)
        readings = []
        lastSeen = nil
        rssi = nil
        state = .waitingForWatch
        stopPicking()
        connectToWatch()
    }

    func lockNow() {
        let called = ScreenLocker.lock()
        state = .waitingForWatch

        // Don't trust the private call blindly. If the screen hasn't reported locked
        // a few seconds later, sleep the display as a backup.
        DispatchQueue.main.asyncAfter(deadline: .now() + (called ? 3 : 0)) { [weak self] in
            guard let self, !self.screenLocked else { return }
            NSLog("Proximity Watch: lock didn't take, sleeping the display instead")
            ScreenLocker.sleepDisplay()
        }
    }

    // MARK: - The arm-then-lock rule

    private func tick() {
        if let watch, watch.state == .connected { watch.readRSSI() }
        // Drop a stale average so the menu shows "No signal" instead of an old number.
        if let lastSeen, Date().timeIntervalSince(lastSeen) > noSignalTimeout {
            readings = []
            rssi = nil
        }
        nearbyDevices.removeAll { Date().timeIntervalSince($0.lastSeen) > 10 }
        evaluate()
    }

    private func evaluate() {
        guard isEnabled else { state = .paused; return }
        guard central.state == .poweredOn else { state = .bluetoothOff; return }
        guard watchID != nil else { state = .noWatchChosen; return }
        guard !screenLocked else { state = .waitingForWatch; return }

        switch state {
        case .armed:
            if watchIsAway { state = .leaving(since: Date()) }
        case .leaving(let since):
            if !watchIsAway {
                state = .armed
            } else if Date().timeIntervalSince(since) >= lockDelay {
                lockNow()
            }
        default:
            state = (watchIsNear && userIsActive) ? .armed : .waitingForWatch
        }
    }

    private var watchIsNear: Bool {
        guard let rssi, let lastSeen, Date().timeIntervalSince(lastSeen) < 10 else { return false }
        return Double(rssi) >= lockThreshold + armMargin
    }

    private var watchIsAway: Bool {
        guard let rssi, let lastSeen, Date().timeIntervalSince(lastSeen) < noSignalTimeout else { return true }
        return Double(rssi) < lockThreshold
    }

    private var userIsActive: Bool {
        // ~0 is kCGAnyInputEventType: the time since any key press, click, or mouse move.
        guard let anyInput = CGEventType(rawValue: ~0) else { return false }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < activeWindow
    }

    /// Averages the last five readings, since single Bluetooth readings jump around a lot.
    private func record(rssi value: Int) {
        guard value < 0 else { return } // 127 means "no reading"
        readings.append(value)
        if readings.count > 5 { readings.removeFirst() }
        rssi = readings.reduce(0, +) / readings.count
        lastSeen = Date()
    }

    private func observeScreenLock() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.evaluate()
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.evaluate()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state = .waitingForWatch
        }
        // Fast user switching: another account took over the screen, so treat it like a lock.
        workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.evaluate()
        }
        workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.evaluate()
        }
    }

    // MARK: - Bluetooth plumbing

    private func startScanning() {
        // Allow duplicates so every advertisement updates the signal, not just the first one.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Keeps a connection open to the watch so we can ask for its signal strength every second.
    /// When the watch goes out of range, the pending connect waits until it comes back.
    private func connectToWatch() {
        guard let watchID, central.state == .poweredOn else { return }
        if watch == nil { watch = central.retrievePeripherals(withIdentifiers: [watchID]).first }
        if let watch, watch.state == .disconnected { central.connect(watch) }
    }

    private static func isAppleDevice(_ advertisementData: [String: Any]) -> Bool {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return false }
        return data.starts(with: [0x4C, 0x00]) // Apple's Bluetooth company ID
    }
}

extension WatchMonitor: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
            connectToWatch()
        } else {
            // CoreBluetooth invalidates peripherals when Bluetooth resets. Start fresh.
            watch = nil
            readings = []
            rssi = nil
            lastSeen = nil
        }
        evaluate()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if peripheral.identifier == watchID {
            record(rssi: RSSI.intValue)
            if watch == nil {
                watch = peripheral
                connectToWatch()
            }
        }

        guard isPicking, Self.isAppleDevice(advertisementData) else { return }
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unnamed Apple device"
        let device = NearbyDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: Date())
        if let index = nearbyDevices.firstIndex(where: { $0.id == device.id }) {
            nearbyDevices[index] = device
        } else {
            nearbyDevices.append(device)
        }
        nearbyDevices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectToWatch()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connectToWatch() }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil { record(rssi: RSSI.intValue) }
    }
}
