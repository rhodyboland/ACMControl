//
//  BluetoothManager.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import CoreBluetooth
import SwiftUI
import UIKit

struct ACMDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let serialNumber: String
    let displayName: String
    let rssi: Int
}

enum InverterState {
    case off
    case on
    case error
}

/// Represents the various data points we might want to show on CarPlay.
enum CarPlayDataKey: String, CaseIterable, Codable {
    case batteryVoltage
    case currentUsage
    case batteryPercentage
    case batteryTemp1
    case solarVoltage
    case solarCurrent
    case solarPower
    case sensor1
    
    var displayName: String {
        switch self {
        case .batteryVoltage:    return "Battery Voltage"
        case .currentUsage:      return "Current Usage"
        case .batteryPercentage: return "Battery SOC"
        case .batteryTemp1:      return "Battery Temp 1"
        case .solarVoltage:      return "Solar Voltage"
        case .solarCurrent:      return "Solar Current"
        case .solarPower:        return "Solar Power"
        case .sensor1:           return "Sensor 1"
        }
    }
}

enum BatteryDetailsProtocol: String, CaseIterable, Codable, Identifiable {
    case jkBms = "JK"
    case victronBMV = "BMV"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .jkBms:
            return "JK BMS"
        case .victronBMV:
            return "Victron BMV Shunt"
        }
    }
}

enum SolarChargerProtocol: String, CaseIterable, Codable, Identifiable {
    case victron = "VIC"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .victron:
            return "Victron VE.Direct"
        }
    }
}

enum SensorInputType: String, CaseIterable, Codable, Identifiable {
    case none
    case temperature
    case analogVoltage
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none:
            return "Not Installed"
        case .temperature:
            return "Temperature Sensor"
        case .analogVoltage:
            return "Analog Voltage"
        }
    }
}

enum ExternalSwitchType: String, CaseIterable, Codable, Identifiable {
    case none
    case toggleInput
    case momentaryInput
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none:
            return "Not Installed"
        case .toggleInput:
            return "Toggle Switch"
        case .momentaryInput:
            return "Momentary Switch"
        }
    }
}

enum InverterControlMode: String, CaseIterable, Codable, Identifiable {
    case lowCurrentEnable
    case stateSense
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .lowCurrentEnable:
            return "Low Current Enable"
        case .stateSense:
            return "Enable + State Sense"
        }
    }
}



/// A class responsible for handling all Bluetooth interactions with the ESP32-based ACM module.
/// It exposes published properties for battery, solar, and channel states, as well as the Subsystem objects for real-time UI updates.
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private static let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private static let deviceNamePrefix = "ESP32_ACM_"
    private static let legacyDeviceName = "ESP32_ACM"
    
    // MARK: - Bluetooth Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var discoveredPeripheralsBySerial: [String: CBPeripheral] = [:]
    
    static let shared = BluetoothManager()
    
    // MARK: - Published Properties (Battery / Solar Data)
    @Published var batteryPercentage: Float = 50
    @Published var batteryVoltage: Float = 0.0
    @Published var batteryCellVoltage: Float = 0.0
    @Published var batteryCellTemp1: Float = 0.0
    @Published var currentUsage: Float = 0.0
    @Published var currentUsageOut: Float = 0.0
    
    @Published var solarCharging: Int = 0
    @Published var solarVoltage: Float = 0.0
    @Published var solarCurrent: Float = 0.0
    @Published var solarPower: Float = 0.0
    @Published var serialState: Bool = true
    @Published var serialState2: Bool = true
    
    @Published var inverterState: InverterState = .off
    
    @Published var sensor1: Float = 0.0
    
    /// Subsystem objects for real-time UI updates:
    @Published var batterySubsystem: Subsystem
    @Published var solarSubsystem: Subsystem
    @Published var sensorSubsystem: Subsystem
    
    // MARK: - Solar Charging State
    enum SolarChargingState: Int {
        case off = 0
        case fault = 2
        case bulk = 3
        case absorption = 4
        case float = 5
        case equalizeManual = 7
        case startingUp = 245
        case autoEqualize = 247
        case externalControl = 252
        case unknown

        var description: String {
            switch self {
            case .off: return "Off"
            case .fault: return "Fault"
            case .bulk: return "Bulk"
            case .absorption: return "Absorption"
            case .float: return "Float"
            case .equalizeManual: return "Equalize (Manual)"
            case .startingUp: return "Starting-up"
            case .autoEqualize: return "Auto Equalize / Recondition"
            case .externalControl: return "External Control"
            case .unknown: return "Unknown"
            }
        }
    }
    
    enum BatteryState: Int {
        case charging = 0
        case discharging = 1
        case protection = 2
        case unknown
        
        var description: String {
            switch self {
            case .charging: return "Charging"
            case .discharging: return "Discharging"
            case .protection: return "Protection"
            case .unknown: return "Unknown"
            }
        }
    }


    
    func setInverterState(on: Bool) {
        // Example: "I1X" => 'I' (inverter), '1' (inverter #), then '1' or '0'
        let command = "I1" + (on ? "1" : "0")
        controlAccessory(command: command)
        // The actual state gets updated in parseReceivedData()
        // once the device returns the new "I:" voltage
    }
    
    // MARK: - Published Properties (Accessory States)
    @Published var lowCurrentStates: [Bool] = Array(repeating: false, count: 8)
    @Published var lowCurrentBrightness: [Float] = Array(repeating: 1.0, count: 8)
    @Published var lowCurrents: [Float] = Array(repeating: 0.0, count: 8)
    
    @Published var mediumCurrentStates: [Bool] = Array(repeating: false, count: 2)
    @Published var mediumCurrents: [Float] = Array(repeating: 0.0, count: 2)
    
    // MARK: - Published Properties (Configuration)
    @Published var cutOutVoltage: Float = 11.8
    @Published var cutInVoltage: Float = 12.2
    @Published var autoCutoffEnabled: Bool = true
    @Published var alwaysOnChannels: [Bool] = Array(repeating: false, count: 10)
    @Published var priorityChannels: [Bool] = Array(repeating: false, count: 10)
    @Published var advancedBatteryDetailsEnabled: Bool = false
    @Published var batteryDetailsProtocol: BatteryDetailsProtocol = .jkBms
    @Published var batteryCapacityAh: Float = 100.0
    @Published var solarChargerEnabled: Bool = false
    @Published var solarChargerProtocol: SolarChargerProtocol = .victron
    @Published var sensorsEnabled: Bool = false
    @Published var sensor1Type: SensorInputType = .temperature
    @Published var sensor2Type: SensorInputType = .none
    @Published var externalSwitch1Type: ExternalSwitchType = .none
    @Published var externalSwitch2Type: ExternalSwitchType = .none
    @Published var inverterControlEnabled: Bool = false
    @Published var inverterControlMode: InverterControlMode = .lowCurrentEnable
    @Published var ledBrightnessEnabled: Bool = true
    @Published var bmvConsumedAmpHours: Float = 0.0
    @Published var bmvTimeToGoMinutes: Int = 0
    
    // MARK: - Published Property for Output Names
    @Published var lowCurrentOutputNames: [String] = (1...8).map { "LC\($0)" }
    @Published var mediumCurrentOutputNames: [String] = (1...2).map { "MC\($0)" }
    
    // MARK: - Published Property for Connection Status
    @Published var isConnected: Bool = false
    @Published var pairedSerialNumber: String? = nil
    @Published var connectedSerialNumber: String? = nil
    @Published var discoveredDevices: [ACMDiscoveredDevice] = []
    @Published var isScanningForPairing: Bool = false
    
    // Flag to control switch updates (once on connection)
    private var shouldUpdateSwitches: Bool = false
    private var batteryCurrentSamples: [(timestamp: Date, current: Float)] = []
    
    // MARK: - CarPlay Data Selection
    /// Which data items the user wants to see on CarPlay. Defaults to 4 items.
    @Published var selectedCarPlayDataKeys: [CarPlayDataKey] = [
        .batteryVoltage,
        .currentUsage,
        .batteryPercentage,
        .batteryTemp1
    ]
    /// Which outputs the user wants to see in CarPlay’s control screen. Defaults to first 4 low-current.
    @Published var selectedCarPlayOutputs: [Int] = [0, 1, 2, 3]
    
    // A helper to retrieve a textual value for each CarPlayDataKey
    func getCarPlayValue(for key: CarPlayDataKey) -> String {
        switch key {
        case .batteryVoltage:
            return String(format: "%.2f V", batteryVoltage)
        case .currentUsage:
            return String(format: "%.2f A", currentUsage)
        case .batteryPercentage:
            // Depending on whether serialState2 is off, you might do an LFP estimate.
            // For simplicity, just use batteryPercentage as is:
            return String(format: "%.0f%%", batteryPercentage)
        case .batteryTemp1:
            if !advancedBatteryDetailsEnabled {
                return "Not Installed"
            }
            return String(format: "%.1f °C", batteryCellTemp1)
        case .solarVoltage:
            if !isSolarAvailable { return "Not Installed" }
            return String(format: "%.2f V", solarVoltage)
        case .solarCurrent:
            if !isSolarAvailable { return "Not Installed" }
            return String(format: "%.2f A", solarCurrent)
        case .solarPower:
            if !isSolarAvailable { return "Not Installed" }
            return String(format: "%.2f W", solarPower)
        case .sensor1:
            if !sensorsEnabled { return "Not Installed" }
            return String(format: "%.2f °C", sensor1)
        }
    }
    
    // MARK: - Loading & Saving for CarPlay
    private struct CarPlayUserConfig: Codable {
        let dataKeys: [CarPlayDataKey]
        let outputIndices: [Int]
    }
    
    // MARK: - Initialization
    override init() {
        // Create subsystem objects with placeholder data
        self.batterySubsystem = Subsystem(
            name: "Battery",
            state: "Unknown",
            dataItems: []
        )
        self.solarSubsystem = Subsystem(
            name: "Solar",
            state: "Unknown",
            dataItems: []
        )
        self.sensorSubsystem = Subsystem(
            name: "Sensors",
            state: "Unknown",
            dataItems: []
        )
        
        super.init()
        // Attempt to load existing configuration from user defaults
        loadUserConfiguration()
        loadCarPlayConfiguration()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadOutputNames()
        
        // Add observers for app lifecycle events
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle Handlers
    @objc private func appDidBecomeActive() {
        print("App became active. Checking Bluetooth connection status.")
        checkConnectionStatus()
    }
    
    @objc private func appWillResignActive() {
        print("App will resign active. Current connection status: \(isConnected)")
        // Optional: any cleanup on background
    }
    
    private struct ACMUserConfiguration: Codable {
        let cutOutVoltage: Float
        let cutInVoltage: Float
        let autoCutoffEnabled: Bool
        let alwaysOnChannels: [Bool]
        let priorityChannels: [Bool]
        let advancedBatteryDetailsEnabled: Bool?
        let batteryDetailsProtocol: BatteryDetailsProtocol?
        let batteryCapacityAh: Float?
        let solarChargerEnabled: Bool?
        let solarChargerProtocol: SolarChargerProtocol?
        let sensorsEnabled: Bool?
        let sensor1Type: SensorInputType?
        let sensor2Type: SensorInputType?
        let externalSwitch1Type: ExternalSwitchType?
        let externalSwitch2Type: ExternalSwitchType?
        let inverterControlEnabled: Bool?
        let inverterControlMode: InverterControlMode?
        let ledBrightnessEnabled: Bool?
        let pairedSerialNumber: String?
    }

    func loadUserConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: "ACMUserConfiguration") else { return }
        guard let decoded = try? JSONDecoder().decode(ACMUserConfiguration.self, from: data) else { return }
        
        // Restore the values
        self.cutOutVoltage     = decoded.cutOutVoltage
        self.cutInVoltage      = decoded.cutInVoltage
        self.autoCutoffEnabled = decoded.autoCutoffEnabled
        self.alwaysOnChannels  = decoded.alwaysOnChannels
        self.priorityChannels  = decoded.priorityChannels
        self.advancedBatteryDetailsEnabled = decoded.advancedBatteryDetailsEnabled ?? false
        self.batteryDetailsProtocol = decoded.batteryDetailsProtocol ?? .jkBms
        self.batteryCapacityAh = decoded.batteryCapacityAh ?? 100.0
        self.solarChargerEnabled = decoded.solarChargerEnabled ?? false
        self.solarChargerProtocol = decoded.solarChargerProtocol ?? .victron
        self.sensorsEnabled = decoded.sensorsEnabled ?? false
        self.sensor1Type = decoded.sensor1Type ?? .temperature
        self.sensor2Type = decoded.sensor2Type ?? .none
        self.externalSwitch1Type = decoded.externalSwitch1Type ?? .none
        self.externalSwitch2Type = decoded.externalSwitch2Type ?? .none
        self.inverterControlEnabled = decoded.inverterControlEnabled ?? false
        self.inverterControlMode = decoded.inverterControlMode ?? .lowCurrentEnable
        self.ledBrightnessEnabled = decoded.ledBrightnessEnabled ?? true
        self.pairedSerialNumber = decoded.pairedSerialNumber
        applyFeatureDependencies()
        sanitizeCarPlaySelections()
    }

    func saveUserConfiguration() {
        let config = ACMUserConfiguration(
            cutOutVoltage: self.cutOutVoltage,
            cutInVoltage: self.cutInVoltage,
            autoCutoffEnabled: self.autoCutoffEnabled,
            alwaysOnChannels: self.alwaysOnChannels,
            priorityChannels: self.priorityChannels,
            advancedBatteryDetailsEnabled: self.advancedBatteryDetailsEnabled,
            batteryDetailsProtocol: self.batteryDetailsProtocol,
            batteryCapacityAh: self.batteryCapacityAh,
            solarChargerEnabled: self.solarChargerEnabled,
            solarChargerProtocol: self.solarChargerProtocol,
            sensorsEnabled: self.sensorsEnabled,
            sensor1Type: self.sensor1Type,
            sensor2Type: self.sensor2Type,
            externalSwitch1Type: self.externalSwitch1Type,
            externalSwitch2Type: self.externalSwitch2Type,
            inverterControlEnabled: self.inverterControlEnabled,
            inverterControlMode: self.inverterControlMode,
            ledBrightnessEnabled: self.ledBrightnessEnabled,
            pairedSerialNumber: self.pairedSerialNumber
        )
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "ACMUserConfiguration")
        }
    }
    func loadCarPlayConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: "CarPlayUserConfig") else { return }
        guard let decoded = try? JSONDecoder().decode(CarPlayUserConfig.self, from: data) else { return }
        self.selectedCarPlayDataKeys = decoded.dataKeys
        self.selectedCarPlayOutputs  = decoded.outputIndices
    }
    
    func saveCarPlayConfiguration() {
        let config = CarPlayUserConfig(
            dataKeys: self.selectedCarPlayDataKeys,
            outputIndices: self.selectedCarPlayOutputs
        )
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "CarPlayUserConfig")
        }
    }
    
    var isVictronBMVSelected: Bool {
        advancedBatteryDetailsEnabled && batteryDetailsProtocol == .victronBMV
    }
    
    var isSolarAvailable: Bool {
        solarChargerEnabled && !isVictronBMVSelected
    }
    
    var availableCarPlayDataKeys: [CarPlayDataKey] {
        CarPlayDataKey.allCases.filter { key in
            switch key {
            case .solarVoltage, .solarCurrent, .solarPower:
                return isSolarAvailable
            case .sensor1:
                return sensorsEnabled
            case .batteryTemp1:
                return advancedBatteryDetailsEnabled
            default:
                return true
            }
        }
    }
    
    func applyFeatureDependencies() {
        if isVictronBMVSelected {
            solarChargerEnabled = false
        }
        
        if !advancedBatteryDetailsEnabled {
            bmvConsumedAmpHours = 0
            bmvTimeToGoMinutes = 0
        }
        
        if !advancedBatteryDetailsEnabled || batteryDetailsProtocol != .jkBms {
            batteryCurrentSamples.removeAll()
        }
        
        batteryCapacityAh = max(1.0, batteryCapacityAh)
        
        sanitizeCarPlaySelections()
    }
    
    func sanitizeCarPlaySelections() {
        let availableKeys = Set(availableCarPlayDataKeys)
        selectedCarPlayDataKeys = selectedCarPlayDataKeys.filter { availableKeys.contains($0) }
        
        if selectedCarPlayDataKeys.isEmpty {
            selectedCarPlayDataKeys = availableCarPlayDataKeys.prefix(4).map { $0 }
        }
    }
    
    private func activeBatteryProtocolCode() -> String {
        guard advancedBatteryDetailsEnabled else { return "NONE" }
        return batteryDetailsProtocol.rawValue
    }
    
    private func activeSolarProtocolCode() -> String {
        guard isSolarAvailable else { return "NONE" }
        return solarChargerProtocol.rawValue
    }
    
    private func formattedTimeToGo() -> String {
        guard bmvTimeToGoMinutes > 0 else { return "Unavailable" }
        let hours = bmvTimeToGoMinutes / 60
        let minutes = bmvTimeToGoMinutes % 60
        if hours == 0 {
            return "\(minutes) min"
        }
        return "\(hours)h \(minutes)m"
    }
    
    private func recordBatteryCurrentSample(_ current: Float) {
        let now = Date()
        batteryCurrentSamples.append((timestamp: now, current: current))
        batteryCurrentSamples.removeAll { now.timeIntervalSince($0.timestamp) > 60 }
    }
    
    private func formattedJKTimeRemaining() -> String {
        guard serialState2 else { return "Unavailable" }
        guard batteryCapacityAh > 0 else { return "Set capacity" }
        let dischargeSamples = batteryCurrentSamples
            .map { $0.current }
            .filter { $0 < -0.1 }
        
        guard !dischargeSamples.isEmpty else {
            return currentUsage > 0.1 ? "Charging" : "Unavailable"
        }
        
        let averageDischargeCurrent = abs(dischargeSamples.reduce(0, +) / Float(dischargeSamples.count))
        guard averageDischargeCurrent > 0.1 else { return "Unavailable" }
        
        let clampedPercentage = max(Float(0), min(batteryPercentage, Float(100)))
        let remainingAh = batteryCapacityAh * clampedPercentage / 100.0
        let minutesRemaining = Int((remainingAh / averageDischargeCurrent * 60).rounded())
        return formattedDuration(minutes: minutesRemaining)
    }
    
    private func formattedDuration(minutes: Int) -> String {
        guard minutes > 0 else { return "Unavailable" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 {
            return "\(remainingMinutes) min"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
    
    var pairedDeviceLabel: String {
        pairedSerialNumber ?? "No ACM Paired"
    }
    
    private func serialNumber(fromDeviceName deviceName: String?) -> String? {
        guard let deviceName else { return nil }
        guard deviceName.hasPrefix(Self.deviceNamePrefix) else { return nil }
        let serial = String(deviceName.dropFirst(Self.deviceNamePrefix.count))
        return serial.isEmpty ? nil : serial
    }
    
    private func advertisedName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String? {
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            return localName
        }
        return peripheral.name
    }
    
    private func updateDiscoveredDevice(_ peripheral: CBPeripheral, advertisedName: String?, rssi: NSNumber) {
        guard let serialNumber = serialNumber(fromDeviceName: advertisedName) else { return }
        
        discoveredPeripheralsBySerial[serialNumber] = peripheral
        
        let device = ACMDiscoveredDevice(
            id: peripheral.identifier,
            serialNumber: serialNumber,
            displayName: advertisedName ?? serialNumber,
            rssi: rssi.intValue
        )
        
        if let existingIndex = discoveredDevices.firstIndex(where: { $0.serialNumber == serialNumber }) {
            discoveredDevices[existingIndex] = device
        } else {
            discoveredDevices.append(device)
            discoveredDevices.sort { $0.serialNumber < $1.serialNumber }
        }
    }
    
    private func startScanning(includeAllDevices: Bool = false) {
        guard centralManager.state == .poweredOn else { return }
        let serviceFilter: [CBUUID]? = includeAllDevices ? nil : [Self.serviceUUID]
        centralManager.scanForPeripherals(withServices: serviceFilter, options: nil)
    }
    
    func startPairingScan() {
        discoveredDevices = []
        discoveredPeripheralsBySerial = [:]
        isScanningForPairing = true
        startScanning(includeAllDevices: true)
    }
    
    func stopPairingScan() {
        isScanningForPairing = false
        centralManager.stopScan()
    }
    
    func pair(with device: ACMDiscoveredDevice) {
        pairedSerialNumber = device.serialNumber
        saveUserConfiguration()
        stopPairingScan()
        
        if let currentPeripheral = peripheral, currentPeripheral.identifier != device.id {
            centralManager.cancelPeripheralConnection(currentPeripheral)
        }
        
        guard let targetPeripheral = discoveredPeripheralsBySerial[device.serialNumber] else { return }
        peripheral = targetPeripheral
        characteristic = nil
        connectedSerialNumber = device.serialNumber
        centralManager.connect(targetPeripheral, options: nil)
    }
    
    func clearPairing() {
        pairedSerialNumber = nil
        connectedSerialNumber = nil
        saveUserConfiguration()
        if let currentPeripheral = peripheral {
            centralManager.cancelPeripheralConnection(currentPeripheral)
        }
    }
    
    private func shouldAutoConnect(to peripheral: CBPeripheral, advertisedName: String? = nil) -> Bool {
        let deviceName = advertisedName ?? peripheral.name
        if let pairedSerialNumber {
            return serialNumber(fromDeviceName: deviceName) == pairedSerialNumber
        }
        
        return deviceName == Self.legacyDeviceName
    }
    
    // MARK: - Connection Status Checker
    private func checkConnectionStatus() {
        guard let peripheral = peripheral else {
            isConnected = false
            startScanning(includeAllDevices: pairedSerialNumber != nil)
            print("Peripheral not found. Scanning for peripherals...")
            return
        }
        
        // Check if the peripheral is already connected
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        if connectedPeripherals.contains(peripheral) {
            isConnected = true
            connectedSerialNumber = serialNumber(fromDeviceName: peripheral.name) ?? pairedSerialNumber
            peripheral.delegate = self
            peripheral.discoverServices([Self.serviceUUID])
            print("Peripheral is already connected.")
        } else {
            isConnected = false
            startScanning(includeAllDevices: pairedSerialNumber != nil)
            print("Peripheral not connected. Scanning for peripherals...")
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central Manager state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if let peripheral = self.peripheral {
                let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
                if connectedPeripherals.contains(peripheral) {
                    centralManager.connect(peripheral, options: nil)
                    print("Reconnecting to peripheral: \(peripheral.name ?? "Unknown")")
                } else {
                    startScanning(includeAllDevices: pairedSerialNumber != nil)
                    print("Scanning for peripherals...")
                }
            } else {
                startScanning(includeAllDevices: pairedSerialNumber != nil)
                print("Scanning for peripherals...")
            }
        default:
            print("Bluetooth is not available. State: \(central.state.rawValue)")
            isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = advertisedName(for: peripheral, advertisementData: advertisementData)
        print("Discovered peripheral: \(deviceName ?? "Unknown")")
        updateDiscoveredDevice(peripheral, advertisedName: deviceName, rssi: RSSI)
        
        if shouldAutoConnect(to: peripheral, advertisedName: deviceName) {
            self.peripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
            print("Connecting to \(deviceName ?? "Unknown")...")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectedSerialNumber = self.serialNumber(fromDeviceName: peripheral.name) ?? self.pairedSerialNumber
            self.shouldUpdateSwitches = true // Enable switch updates on (re)connection
        }
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(peripheral.name ?? "Unknown"), error: \(error?.localizedDescription ?? "Unknown Error")")
        DispatchQueue.main.async {
            self.isConnected = false
        }
        attemptReconnection()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown"), error: \(error?.localizedDescription ?? "No Error")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedSerialNumber = nil
        }
        attemptReconnection()
    }
    
    // MARK: - Reconnection Logic
    private func attemptReconnection() {
        guard let peripheral = peripheral else { return }
        print("Attempting to reconnect to \(peripheral.name ?? "Unknown") in 5 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.shouldAutoConnect(to: peripheral) {
                self.centralManager.connect(peripheral, options: nil)
            } else {
                self.startScanning(includeAllDevices: self.pairedSerialNumber != nil)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        if let services = peripheral.services {
            for service in services {
                print("Discovered service: \(service.uuid)")
                peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == Self.characteristicUUID {
                    self.characteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("Found characteristic: \(characteristic.uuid). Enabled notifications.")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        if let value = characteristic.value {
            let receivedString = String(decoding: value, as: UTF8.self)
//            print("Received data: \(receivedString)")
            parseReceivedData(receivedString)
        }
    }
    
    // MARK: - Parsing Method for New Protocol
    /// Parses the data string from the ESP32 for voltage/current info and accessory states.
    private func parseReceivedData(_ data: String) {
        DispatchQueue.main.async {
//            print("Parsing data: \(data)")
            
            // Split the received string by sections
            let sections = data.split(separator: ";")
            for section in sections {
                let parts = section.split(separator: ":")
                guard parts.count == 2 else {
                    print("Invalid section format: \(section)")
                    continue
                }
                let identifier = parts[0]
                let content = parts[1]
                
                switch identifier {
                case "V": // Voltage and Current Section
                    let values = content.split(separator: ",")
                    if values.count == 13 {
                        // Battery Voltage
                        self.batteryVoltage = Float(strtoul(String(values[0]), nil, 16)) / 100.0
                        
                        let decodedBmsCurrent = (Float(strtoul(String(values[1]), nil, 16)) / 10.0) - 512.0
                        
                        // High-side driver output current is encoded as amps * 100.
                        let decodedOutputCurrent = Float(strtoul(String(values[2]), nil, 16)) / 100.0
                        let bmsIsConnected = (values[12] == "1")
                        self.currentUsageOut = decodedOutputCurrent
                        self.currentUsage = bmsIsConnected ? decodedBmsCurrent : decodedOutputCurrent
                        if self.advancedBatteryDetailsEnabled && self.batteryDetailsProtocol == .jkBms && bmsIsConnected {
                            self.recordBatteryCurrentSample(decodedBmsCurrent)
                        }
                        
                        // Solar Voltage
                        self.solarVoltage = Float(strtoul(String(values[3]), nil, 16)) / 100000.0
                        // Solar Current
                        self.solarCurrent = Float(strtoul(String(values[4]), nil, 16)) / 100.0
                        // Solar Power
                        self.solarPower = Float(strtoul(String(values[5]), nil, 16)) / 100.0
                        // Solar Charging State
                        self.solarCharging = Int(strtoul(String(values[6]), nil, 16))
                        
                        // Battery Cell Voltage Avg
                        self.batteryCellVoltage = Float(strtoul(String(values[7]), nil, 16)) / 100.0
                        
                        // Battery Cell Temp1
                        self.batteryCellTemp1 = Float(strtoul(String(values[8]), nil, 16)) / 100.0
                        
                        // Battery SOC
                        self.batteryPercentage = Float(strtoul(String(values[9]), nil, 16)) / 100.0
                        
                        // Sensor 1
                        self.sensor1 = Float(strtoul(String(values[10]), nil, 16)) / 100.0
                        
                        // Serial Connection State Victron
                        self.serialState = (values[11] == "1")
                        // Serial Connection State Victron
                        self.serialState2 = bmsIsConnected
                        
                        // Debug prints
//                        print("Battery Voltage Updated: \(self.batteryVoltage) V")
//                        print("Current Usage Updated: \(self.currentUsage) A")
//                        print("Solar Voltage Updated: \(self.solarVoltage) V")
//                        print("Solar Current Updated: \(self.solarCurrent) A")
//                        print("Solar Power Updated: \(self.solarPower) W")
//                        print("Solar Charging Updated: \(self.solarCharging)")
//                        print("Battery Cell Voltage Avg Updated: \(self.batteryCellVoltage) V")
//                        print("Battery Cell Temp1 Updated: \(self.batteryCellTemp1) C")
//                        print("Battery SOC Updated: \(self.batteryPercentage) %")
//                        print("Sensor 1 Updated: \(self.sensor1) C")
//                        print("Serial ConnectionVictron: \(self.serialState)")
//                        print("Serial ConnectionBMS: \(self.serialState2)")
                    } else {
                        print("Invalid number of voltage/current values: \(values.count)")
                    }
                case "L": // Low Current Channels Section
                    let channels = content.split(separator: ",")
                    if channels.count != 8 {
                        print("Invalid number of LC channels: \(channels.count)")
                        break
                    }
                    for (index, channel) in channels.enumerated() {
                        // Format: "1FF3E8" => Example (state + brightness + currentHex)
                        // The code you have is somewhat simplified. Adjust parsing as needed:
                        // In original code, it looked like stateHex + brightnessHex + currentHex
                        // This part depends on your actual custom format
                        
                        if channel.count >= 4 {
                            let stateChar = channel.prefix(1)
                            let brightnessHex = channel.dropFirst(1).prefix(2)
                            let currentHex = channel.dropFirst(3) // the rest are current
                            
                            // State
                            let state = (stateChar == "1")
                            // Brightness from 0..255
                            let brightnessValue = Float(strtoul(String(brightnessHex), nil, 16))
                            let brightness = brightnessValue / 255.0
                            // Current (assuming scaled by 1000 or 100?), you'll need to parse
                            let currentFloat = Float(strtoul(String(currentHex), nil, 16)) / 1000.0
                            
                            if self.shouldUpdateSwitches {
                                self.lowCurrentStates[index] = state
                                self.lowCurrentBrightness[index] = brightness
                                self.lowCurrents[index] = currentFloat
                                print("Parsed LC\(index + 1) - State: \(state), Brightness: \(brightness), Current: \(currentFloat) A")
                            } else {
                                // Only update brightness/current, do not override state
                                self.lowCurrentBrightness[index] = brightness
                                self.lowCurrents[index] = currentFloat
//                                print("Updated LC\(index + 1) Brightness: \(brightness), Current: \(currentFloat) A")
                            }
                        } else {
                            print("Invalid LC channel format: \(channel)")
                        }
                    }
                    if self.shouldUpdateSwitches {
                        self.shouldUpdateSwitches = false
                    }
                case "M": // Medium Current Channels Section
                    let channels = content.split(separator: ",")
                    if channels.count != 2 {
                        print("Invalid number of MC channels: \(channels.count)")
                        break
                    }
                    for (index, channel) in channels.enumerated() {
                        // Format example: "13FA" => stateChar + currentHex
                        if channel.count >= 2 {
                            let stateChar = channel.prefix(1)
                            let currentHex = channel.dropFirst(1)
                            
                            let state = (stateChar == "1")
                            let currentFloat = Float(strtoul(String(currentHex), nil, 16)) / 1000.0
                            
                            if self.shouldUpdateSwitches {
                                self.mediumCurrentStates[index] = state
                                self.mediumCurrents[index] = currentFloat
                                print("Parsed MC\(index + 1) - State: \(state), Current: \(currentFloat) A")
                            } else {
                                self.mediumCurrents[index] = currentFloat
//                                print("Updated MC\(index + 1) Current: \(currentFloat) A")
                            }
                        } else {
                            print("Invalid MC channel format: \(channel)")
                        }
                    }
                    if self.shouldUpdateSwitches {
                        self.shouldUpdateSwitches = false
                    }
                case "I":
                    let invValueHex = String(content)
                    let invValueInt = strtoul(invValueHex, nil, 16) // e.g. 0x000F => 15 decimal
                    let voltageFloat = Float(invValueInt) / 100.0   // scale by 100
                    // - <= 0.2 V => OFF
                    // - <= 0.6 V => ON
                    // - else => ERROR
                    if voltageFloat <= 0.3 {
                        self.inverterState = .off
                    } else if voltageFloat <= 0.7 {
                        self.inverterState = .on
                    } else {
                        self.inverterState = .error
                    }
//                    print("Inverter voltage: \(voltageFloat), state: \(inverterState)")
                case "B":
                    let values = content.split(separator: ",")
                    if values.count == 2 {
                        self.bmvConsumedAmpHours = (Float(values[0]) ?? 0.0) / 1000.0
                        self.bmvTimeToGoMinutes = Int(values[1]) ?? 0
                    } else {
                        print("Invalid number of BMV values: \(values.count)")
                    }
                case "SN":
                    self.connectedSerialNumber = String(content)
                default:
                    print("Unknown data component: \(section)")
                }
            }
            
            // After parsing everything, update the subsystem objects so the UI refreshes in real-time
            self.updateSubsystems()
        }
    }
    
    func estimateLFPBatteryPercentage(voltage: Float) -> Float {
        // Voltage-capacity data extracted from the image
        let voltageCapacityData: [(voltage: Float, capacity: Float)] = [
            (14.4, 100),
            (13.6, 100),
            (13.4, 99),
            (13.3, 90),
            (13.2, 70),
            (13.1, 40),
            (13.0, 30),
            (12.9, 20),
            (12.8, 17),
            (12.5, 14),
            (12.0, 9),
            (10.0, 0)
        ]

        // Clamp the input voltage to the range of the data
        let clampedVoltage = max(min(voltage, 14.4), 10.0)

        // Perform piecewise linear interpolation
        for i in 1..<voltageCapacityData.count {
            let (v1, c1) = voltageCapacityData[i - 1]
            let (v2, c2) = voltageCapacityData[i]

            if clampedVoltage >= v2 && clampedVoltage <= v1 {
                // Linear interpolation formula
                return c1 + (clampedVoltage - v1) * (c2 - c1) / (v2 - v1)
            }
        }

        return 0 // Default to 0% if something goes wrong
    }

    
    // MARK: - Updating Subsystems
    /// Called after parsing new BLE data to rebuild the subsystem objects for real-time UI updates.
    private func updateSubsystems() {
        let solarChargingState = SolarChargingState(rawValue: solarCharging) ?? .unknown
        let estimatedPercentage: Float
        let chargeState: Int
        if currentUsage > 0.0 {
            chargeState = 0
        } else if currentUsage <= 0.0 {
            chargeState = 1
        } else {
            chargeState = 2
        }
        
        let batteryChargingState = BatteryState(rawValue: chargeState) ?? .unknown

        // Battery Subsystem
        batterySubsystem.name = "Battery"
        if !serialState2 {
            estimatedPercentage = estimateLFPBatteryPercentage(voltage: batteryVoltage)
        } else {
            estimatedPercentage = batteryPercentage
        }
        
                
        
        var batteryItems: [DataItem] = [
            DataItem(
                title: "Battery Voltage",
                value: String(format: "%.2f V", batteryVoltage),
                state: "Normal",
                isDisabled: false
            ),
            DataItem(
                title: "Current Usage",
                value: String(format: "%.2f A", currentUsage),
                state: "Normal",
                isDisabled: false
            ),
            DataItem(
                title: "Battery Charge",
                value: String(format: "%.0f%%", estimatedPercentage),
                state: "Normal",
                isDisabled: false,
                type: .batteryPercentage
            ),
            DataItem(
                title: "Battery State",
                value: batteryChargingState.description,
                state: "Normal",
                isDisabled: false
            )
        ]
        
        if advancedBatteryDetailsEnabled {
            if batteryDetailsProtocol == .jkBms {
                batteryItems.append(
                    DataItem(
                        title: "Battery Temp 1",
                        value: String(format: "%.0f C", batteryCellTemp1),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
                batteryItems.append(
                    DataItem(
                        title: "Battery Avg Cell",
                        value: String(format: "%.2f V", batteryCellVoltage),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
                batteryItems.append(
                    DataItem(
                        title: "Time Remaining",
                        value: formattedJKTimeRemaining(),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
            } else if batteryDetailsProtocol == .victronBMV {
                batteryItems.append(
                    DataItem(
                        title: "Battery Temperature",
                        value: String(format: "%.0f C", batteryCellTemp1),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
                batteryItems.append(
                    DataItem(
                        title: "Consumed Ah",
                        value: String(format: "%.1f Ah", bmvConsumedAmpHours),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
                batteryItems.append(
                    DataItem(
                        title: "Time To Go",
                        value: formattedTimeToGo(),
                        state: "Normal",
                        isDisabled: !serialState2
                    )
                )
            }
        }
        
        batterySubsystem.state = String(format: "%.0f%%", estimatedPercentage)
        batterySubsystem.dataItems = batteryItems
        
        // Solar Subsystem
        solarSubsystem.name = "Solar"
        solarSubsystem.state = solarChargingState.description
        solarSubsystem.dataItems = [
            DataItem(
                title: "Solar Voltage",
                value: String(format: "%.2f V", solarVoltage),
                state: solarChargingState.description,
                isDisabled: !serialState || !isSolarAvailable
            ),
            DataItem(
                title: "Solar Current",
                value: String(format: "%.2f A", solarCurrent),
                state: solarChargingState.description,
                isDisabled: !serialState || !isSolarAvailable
            ),
            DataItem(
                title: "Solar Power",
                value: String(format: "%.2f W", solarPower),
                state: solarChargingState.description,
                isDisabled: !serialState || !isSolarAvailable
            ),
            DataItem(
                title: "Solar State",
                value: solarChargingState.description,
                state: solarChargingState.description,
                isDisabled: !serialState || !isSolarAvailable
            )
        ]
        
        
        // Sensors Subsystem
        sensorSubsystem.name = "Sensors"
        sensorSubsystem.state = String(format: "%.1f C", sensor1)
        sensorSubsystem.dataItems = [
            DataItem(
                title: "Internal Temp Sensor",
                value: String(format: "%.2f C", sensor1),
                state: "Normal",
                isDisabled: !sensorsEnabled
            )
        ]
    }
    
    // MARK: - Send Configuration to ESP32
    func sendConfiguration() {
        guard let characteristic = self.characteristic else {
            print("Characteristic not found. Cannot send configuration.")
            return
        }
        
        // Convert config options to command string
        applyFeatureDependencies()
        
        let configString = "CONFIG CO\(String(format: "%.2f", cutOutVoltage)) CI\(String(format: "%.2f", cutInVoltage)) AC\(autoCutoffEnabled ? "1" : "0") AO\(alwaysOnChannels.map { $0 ? "1" : "0" }.joined()) PR\(priorityChannels.map { $0 ? "1" : "0" }.joined()) FB\(advancedBatteryDetailsEnabled ? "1" : "0") BP\(activeBatteryProtocolCode()) FS\(isSolarAvailable ? "1" : "0") SP\(activeSolarProtocolCode())"
        
        if let data = configString.data(using: .utf8) {
            peripheral?.writeValue(data, for: characteristic, type: .withResponse)
            print("Sent configuration: \(configString)")
            // Save to UserDefaults so we have a local copy
            saveUserConfiguration()
        } else {
            print("Failed to encode configuration string.")
        }
    }
    
    // MARK: - Set Low Current State
    func setLowCurrentState(index: Int, state: Bool) {
        guard index >= 0 && index < lowCurrentStates.count else {
            print("Invalid index for low current state.")
            return
        }
        self.lowCurrentStates[index] = state
        let command = "L\(index + 1)\(state ? "1" : "0")"
        print("Sending command to set LC\(index + 1) to \(state ? "ON" : "OFF")")
        controlAccessory(command: command)
    }
    
    // MARK: - Set Medium Current State
    func setMediumCurrentState(index: Int, state: Bool) {
        guard index >= 0 && index < mediumCurrentStates.count else {
            print("Invalid index for medium current state.")
            return
        }
        self.mediumCurrentStates[index] = state
        let command = "M\(index + 1)\(state ? "1" : "0")"
        print("Sending command to set MC\(index + 1) to \(state ? "ON" : "OFF")")
        controlAccessory(command: command)
    }
    
    // MARK: - Inverter State (Example)
    func setInverterState(index: Int, state: Bool) {
        let command = "I\(index + 1)\(state ? "1" : "0")"
        print("Sending command to set Inverter\(index + 1) to \(state ? "ON" : "OFF")")
        controlAccessory(command: command)
    }
    
    // MARK: - Control Commands
    func controlAccessory(command: String) {
        guard let characteristic = self.characteristic else {
            print("Characteristic not found. Cannot send command: \(command)")
            return
        }
        guard let data = command.data(using: .utf8) else {
            print("Failed to encode command: \(command)")
            return
        }
        peripheral?.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }
    
    // MARK: - Load and Save Output Names
    private func loadOutputNames() {
        if let savedLCNames = UserDefaults.standard.array(forKey: "lowCurrentOutputNames") as? [String], savedLCNames.count == 8 {
            lowCurrentOutputNames = savedLCNames
        }
        if let savedMCNames = UserDefaults.standard.array(forKey: "mediumCurrentOutputNames") as? [String], savedMCNames.count == 2 {
            mediumCurrentOutputNames = savedMCNames
        }
        print("Loaded Output Names:")
        print("Low Current: \(lowCurrentOutputNames)")
        print("Medium Current: \(mediumCurrentOutputNames)")
    }
    
    func saveOutputNames() {
        UserDefaults.standard.set(lowCurrentOutputNames, forKey: "lowCurrentOutputNames")
        UserDefaults.standard.set(mediumCurrentOutputNames, forKey: "mediumCurrentOutputNames")
        print("Saved Output Names:")
        print("Low Current: \(lowCurrentOutputNames)")
        print("Medium Current: \(mediumCurrentOutputNames)")
    }
    
    // MARK: - Renaming Methods
    func renameLowCurrentOutput(at index: Int, to newName: String) {
        guard index >= 0 && index < lowCurrentOutputNames.count else {
            print("Invalid index for renaming LC output.")
            return
        }
        lowCurrentOutputNames[index] = newName
        saveOutputNames()
        print("Renamed LC\(index + 1) to \(newName)")
    }
    
    func renameMediumCurrentOutput(at index: Int, to newName: String) {
        guard index >= 0 && index < mediumCurrentOutputNames.count else {
            print("Invalid index for renaming MC output.")
            return
        }
        mediumCurrentOutputNames[index] = newName
        saveOutputNames()
        print("Renamed MC\(index + 1) to \(newName)")
    }
}
