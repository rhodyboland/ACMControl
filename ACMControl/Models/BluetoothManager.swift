//
//  BluetoothManager.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import CoreBluetooth
import SwiftUI
import UIKit

enum InverterState {
    case off
    case on
    case error
}

/// A class responsible for handling all Bluetooth interactions with the ESP32-based ACM module.
/// It exposes published properties for battery, solar, and channel states, as well as the Subsystem objects for real-time UI updates.
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Bluetooth Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    
    // MARK: - Published Properties (Battery / Solar Data)
    @Published var batteryPercentage: Int = 50
    @Published var batteryVoltage: Float = 0.0
    @Published var currentUsage: Float = 0.0
    
    @Published var solarCharging: Int = 0
    @Published var solarVoltage: Float = 0.0
    @Published var solarCurrent: Float = 0.0
    @Published var solarPower: Float = 0.0
    @Published var serialState: Bool = true
    
    @Published var inverterState: InverterState = .off
    
    /// Subsystem objects for real-time UI updates:
    @Published var batterySubsystem: Subsystem
    @Published var solarSubsystem: Subsystem
    
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
    
    // MARK: - Published Property for Output Names
    @Published var lowCurrentOutputNames: [String] = (1...8).map { "LC\($0)" }
    @Published var mediumCurrentOutputNames: [String] = (1...2).map { "MC\($0)" }
    
    // MARK: - Published Property for Connection Status
    @Published var isConnected: Bool = false
    
    // Flag to control switch updates (once on connection)
    private var shouldUpdateSwitches: Bool = false
    
    

    
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
        
        super.init()
        // Attempt to load existing configuration from user defaults
        loadUserConfiguration()
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
    }

    func saveUserConfiguration() {
        let config = ACMUserConfiguration(
            cutOutVoltage: self.cutOutVoltage,
            cutInVoltage: self.cutInVoltage,
            autoCutoffEnabled: self.autoCutoffEnabled,
            alwaysOnChannels: self.alwaysOnChannels,
            priorityChannels: self.priorityChannels
        )
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "ACMUserConfiguration")
        }
    }
    
    // MARK: - Connection Status Checker
    private func checkConnectionStatus() {
        guard let peripheral = peripheral else {
            isConnected = false
            centralManager.scanForPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")], options: nil)
            print("Peripheral not found. Scanning for peripherals...")
            return
        }
        
        // Check if the peripheral is already connected
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")])
        if connectedPeripherals.contains(peripheral) {
            isConnected = true
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")])
            print("Peripheral is already connected.")
        } else {
            isConnected = false
            centralManager.scanForPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")], options: nil)
            print("Peripheral not connected. Scanning for peripherals...")
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central Manager state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if let peripheral = self.peripheral {
                let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")])
                if connectedPeripherals.contains(peripheral) {
                    centralManager.connect(peripheral, options: nil)
                    print("Reconnecting to peripheral: \(peripheral.name ?? "Unknown")")
                } else {
                    centralManager.scanForPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")], options: nil)
                    print("Scanning for peripherals...")
                }
            } else {
                centralManager.scanForPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")], options: nil)
                print("Scanning for peripherals...")
            }
        default:
            print("Bluetooth is not available. State: \(central.state.rawValue)")
            isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        if peripheral.name == "ESP32_ACM" {
            self.peripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
            print("Connecting to ESP32_ACM...")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnected = true
            self.shouldUpdateSwitches = true // Enable switch updates on (re)connection
        }
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")])
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
        }
        attemptReconnection()
    }
    
    // MARK: - Reconnection Logic
    private func attemptReconnection() {
        guard let peripheral = peripheral else { return }
        print("Attempting to reconnect to \(peripheral.name ?? "Unknown") in 5 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.centralManager.connect(peripheral, options: nil)
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
                peripheral.discoverCharacteristics([CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")], for: service)
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
                if characteristic.uuid == CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
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
            print("Received data: \(receivedString)")
            parseReceivedData(receivedString)
        }
    }
    
    // MARK: - Parsing Method for New Protocol
    /// Parses the data string from the ESP32 for voltage/current info and accessory states.
    private func parseReceivedData(_ data: String) {
        DispatchQueue.main.async {
            print("Parsing data: \(data)")
            
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
                    if values.count == 7 {
                        // Battery Voltage
                        self.batteryVoltage = Float(strtoul(String(values[0]), nil, 16)) / 100.0
                        // Current Usage
                        self.currentUsage = Float(strtoul(String(values[1]), nil, 16)) / 100000.0
                        
                        // Solar Voltage
                        self.solarVoltage = Float(strtoul(String(values[2]), nil, 16)) / 100000.0
                        // Solar Current
                        self.solarCurrent = Float(strtoul(String(values[3]), nil, 16)) / 100.0
                        // Solar Power
                        self.solarPower = Float(strtoul(String(values[4]), nil, 16)) / 100.0
                        // Solar Charging State
                        self.solarCharging = Int(strtoul(String(values[5]), nil, 16))
                        // Serial Connection State
                        self.serialState = (values[6] == "1")
                        
                        // Debug prints
                        print("Battery Voltage Updated: \(self.batteryVoltage) V")
                        print("Current Usage Updated: \(self.currentUsage) A")
                        print("Solar Voltage Updated: \(self.solarVoltage) V")
                        print("Solar Current Updated: \(self.solarCurrent) A")
                        print("Solar Power Updated: \(self.solarPower) W")
                        print("Solar Charging Updated: \(self.solarCharging)")
                        print("Serial Connection: \(self.serialState)")
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
                                print("Updated LC\(index + 1) Brightness: \(brightness), Current: \(currentFloat) A")
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
                                print("Updated MC\(index + 1) Current: \(currentFloat) A")
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
        
        // Battery Subsystem
        batterySubsystem.name = "Battery"
    
        let estimatedPercentage = estimateLFPBatteryPercentage(voltage: batteryVoltage)
            
        
        batterySubsystem.state = String(format: "%.0f%%", estimatedPercentage)  // Just using batteryPercentage
        batterySubsystem.dataItems = [
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
                title: "Battery Percentage",
                value: String(format: "%.2f%", estimatedPercentage),
                state: "Normal",
                isDisabled: false,
                type: .batteryPercentage
            )
        ]
        
        // Solar Subsystem
        solarSubsystem.name = "Solar"
        solarSubsystem.state = solarChargingState.description
        solarSubsystem.dataItems = [
            DataItem(
                title: "Solar Voltage",
                value: String(format: "%.2f V", solarVoltage),
                state: solarChargingState.description,
                isDisabled: !serialState
            ),
            DataItem(
                title: "Solar Current",
                value: String(format: "%.2f A", solarCurrent),
                state: solarChargingState.description,
                isDisabled: !serialState
            ),
            DataItem(
                title: "Solar Power",
                value: String(format: "%.2f W", solarPower),
                state: solarChargingState.description,
                isDisabled: !serialState
            ),
            DataItem(
                title: "Solar State",
                value: solarChargingState.description,
                state: solarChargingState.description,
                isDisabled: !serialState
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
        let configString = "CONFIG CO\(String(format: "%.2f", cutOutVoltage)) CI\(String(format: "%.2f", cutInVoltage)) AC\(autoCutoffEnabled ? "1" : "0") AO\(alwaysOnChannels.map { $0 ? "1" : "0" }.joined()) PR\(priorityChannels.map { $0 ? "1" : "0" }.joined())"
        
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
