//
//  BluetoothManager.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import CoreBluetooth
import SwiftUI
import UIKit // Needed for app lifecycle notifications

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Bluetooth Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    
    // MARK: - Published Properties for Data
    @Published var batteryVoltage: Float = 0.0
    @Published var currentUsage: Float = 0.0
    @Published var solarVoltage: Float = 0.0
    @Published var solarCurrent: Float = 0.0
    @Published var solarPower: Float = 0.0
    @Published var solarCharging: Bool = false
    
    // MARK: - Published Properties for Low Current (LC) Outputs
    @Published var lowCurrentStates: [Bool] = Array(repeating: false, count: 8)
    @Published var lowCurrentBrightness: [Float] = Array(repeating: 1.0, count: 8)
    @Published var lowCurrents: [Float] = Array(repeating: 0.0, count: 8)
    
    // MARK: - Published Properties for Medium Current (MC) Outputs
    @Published var mediumCurrentStates: [Bool] = Array(repeating: false, count: 2)
    @Published var mediumCurrents: [Float] = Array(repeating: 0.0, count: 2)
    
    // MARK: - Published Properties for Configuration
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
    
    // MARK: - Flag to Control Switch Updates
    private var shouldUpdateSwitches: Bool = false
    
    // MARK: - Initialization
    override init() {
        super.init()
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
        // Optional: Handle any cleanup if necessary
    }
    
    // MARK: - Connection Status Checker
    private func checkConnectionStatus() {
        guard let peripheral = peripheral else {
            isConnected = false
            centralManager.scanForPeripherals(withServices: [CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")], options: nil)
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
    
    // MARK: - CBCentralManagerDelegate Methods
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central Manager state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            // Attempt to retrieve and reconnect to the peripheral if possible
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
            print("Bluetooth is not available.")
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
            self.shouldUpdateSwitches = true // Enable switch updates on connection
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
        
        // Delay reconnection attempts to avoid rapid retries
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.centralManager.connect(peripheral, options: nil)
        }
    }
    
    // MARK: - CBPeripheralDelegate Methods
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
                    // Enable notifications to receive continuous updates
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
                    if values.count == 5 {
                        self.batteryVoltage = Float(strtoul(String(values[0]), nil, 16)) / 100.0
                        self.currentUsage = Float(strtoul(String(values[1]), nil, 16)) / 100000.0
                        self.solarVoltage = Float(strtoul(String(values[2]), nil, 16)) / 100.0
                        self.solarCurrent = Float(strtoul(String(values[3]), nil, 16)) / 100.0
                        self.solarCharging = (values[3] == "1")
                        self.solarPower = Float(strtoul(String(values[4]), nil, 16)) / 100.0
                        
                        // Debugging Prints
                        print("Battery Voltage Updated: \(self.batteryVoltage) V")
                        print("Current Usage Updated: \(self.currentUsage) A")
                        print("Solar Voltage Updated: \(self.solarVoltage) V")
                        print("Solar Current Updated: \(self.solarCurrent) A")
                        print("Solar Charging Updated: \(self.solarCharging)")
                        print("Solar Power Updated: \(self.solarPower) W")
                    } else {
                        print("Invalid number of voltage/current values: \(values.count)")
                    }
                case "L": // Load Channels Section
                    let channels = content.split(separator: ",")
                    if channels.count != 8 {
                        print("Invalid number of LC channels: \(channels.count)")
                        break
                    }
                    for (index, channel) in channels.enumerated() {
                        // Expected format: 0ff0 (State + Brightness + Current)
                        if channel.count >= 4 { // Adjusted to handle 4 characters
                            let stateChar = channel.prefix(1)
                            let brightnessHex = channel.dropFirst(1).prefix(2)
                            let currentHex = channel.dropFirst(3).prefix(1) // Adjust based on actual current data
                            
                            // Parse state
                            let state = (stateChar == "1")
                            
                            // Parse brightness
                            let brightness = Float(strtoul(String(brightnessHex), nil, 16)) / 255.0
                            
                            // Parse current (assuming single hex digit for simplicity)
                            let current = Float(strtoul(String(currentHex), nil, 16)) / 10.0 // Adjust divisor as needed
                            
                            // Update switch states only upon initial connection or reconnection
                            if self.shouldUpdateSwitches {
                                self.lowCurrentStates[index] = state
                                self.lowCurrentBrightness[index] = brightness
                                self.lowCurrents[index] = current
                                
                                // Debugging Prints
                                print("Parsed LC\(index + 1) - State: \(self.lowCurrentStates[index]), Brightness: \(self.lowCurrentBrightness[index]), Current: \(self.lowCurrents[index]) A")
                            } else {
                                // Only update brightness and current without altering the switch state
                                self.lowCurrentBrightness[index] = brightness
                                self.lowCurrents[index] = current
                                
                                print("Updated LC\(index + 1) Brightness to \(self.lowCurrentBrightness[index] * 100)%, Current to \(self.lowCurrents[index]) A")
                            }
                        } else {
                            print("Invalid LC channel format: \(channel)")
                        }
                    }
                    if self.shouldUpdateSwitches {
                        self.shouldUpdateSwitches = false // Reset the flag after updating switch states
                    }
                case "M": // Medium Channels Section
                    let channels = content.split(separator: ",")
                    if channels.count != 2 {
                        print("Invalid number of MC channels: \(channels.count)")
                        break
                    }
                    for (index, channel) in channels.enumerated() {
                        // Expected format: 00 (State + Current)
                        if channel.count >= 2 { // Adjusted to handle 2 characters
                            let stateChar = channel.prefix(1)
                            let currentHex = channel.dropFirst(1).prefix(1) // Adjust based on actual current data
                            
                            // Parse state
                            let state = (stateChar == "1")
                            
                            // Parse current (assuming single hex digit for simplicity)
                            let current = Float(strtoul(String(currentHex), nil, 16)) / 10.0 // Adjust divisor as needed
                            
                            // Update switch states only upon initial connection or reconnection
                            if self.shouldUpdateSwitches {
                                self.mediumCurrentStates[index] = state
                                self.mediumCurrents[index] = current
                                
                                // Debugging Prints
                                print("Parsed MC\(index + 1) - State: \(self.mediumCurrentStates[index]), Current: \(self.mediumCurrents[index]) A")
                            } else {
                                // Only update current without altering the switch state
                                self.mediumCurrents[index] = current
                                
                                print("Updated MC\(index + 1) Current to \(self.mediumCurrents[index]) A")
                            }
                        } else {
                            print("Invalid MC channel format: \(channel)")
                        }
                    }
                    if self.shouldUpdateSwitches {
                        self.shouldUpdateSwitches = false // Reset the flag after updating switch states
                    }
                default:
                    print("Unknown data component: \(section)")
                }
            }
        }
    }
    
    // MARK: - Send Configuration to ESP32
    func sendConfiguration() {
        guard let characteristic = self.characteristic else {
            print("Characteristic not found. Cannot send configuration.")
            return
        }
        
        // Convert configuration options to command string
        let configString = "CONFIG CO\(String(format: "%.2f", cutOutVoltage)) CI\(String(format: "%.2f", cutInVoltage)) AC\(autoCutoffEnabled ? "1" : "0") AO\(alwaysOnChannels.map { $0 ? "1" : "0" }.joined()) PR\(priorityChannels.map { $0 ? "1" : "0" }.joined())"
        
        // Send configuration
        if let data = configString.data(using: .utf8) {
            peripheral?.writeValue(data, for: characteristic, type: .withResponse)
            print("Sent configuration: \(configString)")
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
