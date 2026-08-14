//
//  ConfigurationView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//


import Foundation
import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @State private var showDataKeysPicker = false
    @State private var showOutputsPicker  = false
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Voltage Configuration")) {
                    HStack {
                        Text("Cut Out Voltage")
                        Spacer()
                        TextField("11.0", value: $bluetoothManager.cutOutVoltage, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Cut In Voltage")
                        Spacer()
                        TextField("11.5", value: $bluetoothManager.cutInVoltage, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Toggle(isOn: $bluetoothManager.autoCutoffEnabled) {
                        Text("Enable Auto Cutoff")
                    }
                }
                
                Section(header: Text("Installed Features")) {
                    Toggle(
                        "Advanced Battery Details",
                        isOn: Binding(
                            get: { bluetoothManager.advancedBatteryDetailsEnabled },
                            set: { newValue in
                                bluetoothManager.advancedBatteryDetailsEnabled = newValue
                                bluetoothManager.applyFeatureDependencies()
                            }
                        )
                    )
                    
                    if bluetoothManager.advancedBatteryDetailsEnabled {
                        Picker(
                            "Battery Protocol",
                            selection: Binding(
                                get: { bluetoothManager.batteryDetailsProtocol },
                                set: { newValue in
                                    bluetoothManager.batteryDetailsProtocol = newValue
                                    bluetoothManager.applyFeatureDependencies()
                                }
                            )
                        ) {
                            ForEach(BatteryDetailsProtocol.allCases) { protocolOption in
                                Text(protocolOption.displayName).tag(protocolOption)
                            }
                        }
                        
                        if bluetoothManager.batteryDetailsProtocol == .jkBms {
                            HStack {
                                Text("Battery Capacity")
                                Spacer()
                                TextField("100", value: $bluetoothManager.batteryCapacityAh, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 90)
                                Text("Ah")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Toggle(
                        "Solar Charger",
                        isOn: Binding(
                            get: { bluetoothManager.solarChargerEnabled },
                            set: { newValue in
                                bluetoothManager.solarChargerEnabled = newValue
                                bluetoothManager.applyFeatureDependencies()
                            }
                        )
                    )
                    .disabled(bluetoothManager.isVictronBMVSelected)
                    
                    if bluetoothManager.isVictronBMVSelected {
                        Text("Victron BMV uses the ACM VE.Direct port, so solar charging is turned off automatically.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else if bluetoothManager.solarChargerEnabled {
                        Picker("Solar Protocol", selection: $bluetoothManager.solarChargerProtocol) {
                            ForEach(SolarChargerProtocol.allCases) { protocolOption in
                                Text(protocolOption.displayName).tag(protocolOption)
                            }
                        }
                    }
                    
                    Toggle("Sensors", isOn: $bluetoothManager.sensorsEnabled)
                    if bluetoothManager.sensorsEnabled {
                        Picker("Sensor Input 1", selection: $bluetoothManager.sensor1Type) {
                            ForEach(SensorInputType.allCases) { sensorType in
                                Text(sensorType.displayName).tag(sensorType)
                            }
                        }
                        Picker("Sensor Input 2", selection: $bluetoothManager.sensor2Type) {
                            ForEach(SensorInputType.allCases) { sensorType in
                                Text(sensorType.displayName).tag(sensorType)
                            }
                        }
                        Picker("External Switch 1", selection: $bluetoothManager.externalSwitch1Type) {
                            ForEach(ExternalSwitchType.allCases) { switchType in
                                Text(switchType.displayName).tag(switchType)
                            }
                        }
                        Picker("External Switch 2", selection: $bluetoothManager.externalSwitch2Type) {
                            ForEach(ExternalSwitchType.allCases) { switchType in
                                Text(switchType.displayName).tag(switchType)
                            }
                        }
                    }
                    
                    Toggle("Inverter Control", isOn: $bluetoothManager.inverterControlEnabled)
                    if bluetoothManager.inverterControlEnabled {
                        Picker("Inverter Mode", selection: $bluetoothManager.inverterControlMode) {
                            ForEach(InverterControlMode.allCases) { controlMode in
                                Text(controlMode.displayName).tag(controlMode)
                            }
                        }
                    }
                    
                    Toggle("LED Dimming", isOn: $bluetoothManager.ledBrightnessEnabled)
                    Text("This only affects low current channels. Medium current outputs do not support dimming.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("ACM Pairing")) {
                    HStack {
                        Text("Paired ACM")
                        Spacer()
                        Text(bluetoothManager.pairedDeviceLabel)
                            .foregroundColor(.secondary)
                    }
                    
                    if let connectedSerialNumber = bluetoothManager.connectedSerialNumber {
                        HStack {
                            Text("Connected ACM")
                            Spacer()
                            Text(connectedSerialNumber)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if bluetoothManager.isConnected || bluetoothManager.connectedFirmwareVersion != nil {
                        HStack {
                            Text("Firmware")
                            Spacer()
                            Text(bluetoothManager.connectedFirmwareVersion ?? "Waiting for metadata")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if bluetoothManager.isConnected || bluetoothManager.connectedHardwareRevision != nil {
                        HStack {
                            Text("Hardware")
                            Spacer()
                            Text(bluetoothManager.connectedHardwareRevision.map { "R\($0)" } ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if bluetoothManager.isConnected || bluetoothManager.connectedFirmwareVersion != nil {
                        HStack {
                            Text("App Updates")
                            Spacer()
                            Text(bluetoothManager.connectedFirmwareVersion == nil ? "Waiting for metadata" : (bluetoothManager.connectedOTACapable ? "Supported" : "Not Supported"))
                                .foregroundColor(bluetoothManager.connectedOTACapable ? .green : .secondary)
                        }
                    }
                    
                    if bluetoothManager.connectedOTACapable {
                        HStack {
                            Text("OTA Service")
                            Spacer()
                            Text(bluetoothManager.otaServiceAvailable ? "Ready" : "Not Found")
                                .foregroundColor(bluetoothManager.otaServiceAvailable ? .green : .secondary)
                        }
                        
                        if let otaStatus = bluetoothManager.otaStatus {
                            HStack {
                                Text("OTA Status")
                                Spacer()
                                Text(otaStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        
                        if bluetoothManager.otaServiceAvailable {
                            Button("Refresh OTA Status") {
                                bluetoothManager.requestOTAStatus()
                            }
                        }
                        
                        HStack {
                            Text("Bundled Firmware")
                            Spacer()
                            Text(bluetoothManager.bundledFirmwareAvailable ? bluetoothManager.bundledFirmwareDisplayName : "Not bundled")
                                .font(.caption)
                                .foregroundColor(bluetoothManager.bundledFirmwareAvailable ? .secondary : .orange)
                        }
                        
                        if let updateMessage = bluetoothManager.otaUpdateMessage {
                            Text(updateMessage)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        if bluetoothManager.otaUpdateInProgress {
                            ProgressView(value: bluetoothManager.otaUpdateProgress)
                            Button("Abort Firmware Update", role: .destructive) {
                                bluetoothManager.abortFirmwareUpdate()
                            }
                        } else {
                            Button("Install Bundled Firmware") {
                                bluetoothManager.startBundledFirmwareUpdate()
                            }
                            .disabled(!bluetoothManager.otaServiceAvailable || !bluetoothManager.bundledFirmwareAvailable)
                        }
                    }
                    
                    Button(bluetoothManager.isScanningForPairing ? "Stop Scanning" : "Scan for ACMs") {
                        if bluetoothManager.isScanningForPairing {
                            bluetoothManager.stopPairingScan()
                        } else {
                            bluetoothManager.startPairingScan()
                        }
                    }
                    
                    if bluetoothManager.pairedSerialNumber != nil {
                        Button("Clear Pairing", role: .destructive) {
                            bluetoothManager.clearPairing()
                        }
                    }
                    
                    if bluetoothManager.isScanningForPairing && bluetoothManager.discoveredDevices.isEmpty {
                        Text("Scanning for ACM devices...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(bluetoothManager.discoveredDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.serialNumber)
                                Text("RSSI \(device.rssi)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if bluetoothManager.pairedSerialNumber == device.serialNumber {
                                Text("Paired")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Button("Pair") {
                                    bluetoothManager.pair(with: device)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Channel Configuration")) {
                    ForEach(0..<10) { index in
                        HStack {
                            Toggle(isOn: $bluetoothManager.alwaysOnChannels[index]) {
                                Text("Channel \(index + 1) Always On")
                            }
                            Toggle(isOn: $bluetoothManager.priorityChannels[index]) {
                                Text("Channel \(index + 1) Priority")
                            }
                        }
                    }
                }
                
                Section(header: Text("CarPlay Configuration")) {
                    VStack(alignment: .leading) {
                        Text("CarPlay Data Points")
                            .font(.subheadline)
                        
                        Button(action: {
                            showDataKeysPicker = true
                        }) {
                            Text("Select Data Keys (\(bluetoothManager.selectedCarPlayDataKeys.count) selected)")
                                .foregroundColor(.blue)
                        }
                        .sheet(isPresented: $showDataKeysPicker) {
                            CarPlayDataSelectionView(
                                bluetoothManager: bluetoothManager
                            )
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("CarPlay Outputs")
                            .font(.subheadline)
                        
                        Button(action: {
                            showOutputsPicker = true
                        }) {
                            Text("Select Outputs (\(bluetoothManager.selectedCarPlayOutputs.count) selected)")
                                .foregroundColor(.blue)
                        }
                        .sheet(isPresented: $showOutputsPicker) {
                            CarPlayOutputsSelectionView(
                                bluetoothManager: bluetoothManager
                            )
                        }
                    }
                }
            }
            
            // "Send Configuration" Button
            Button(action: {
                bluetoothManager.sendConfiguration()
            }) {
                Text("Send Configuration")
                    .fontWeight(.bold)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(8)
                    .padding([.leading, .trailing, .bottom], 16)
            }
        }
        .navigationTitle("Configuration")
        .onDisappear {
            bluetoothManager.applyFeatureDependencies()
            bluetoothManager.saveUserConfiguration()
        }
    }
}

/// A simple multi-selection screen for picking data keys.
struct CarPlayDataSelectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothManager.availableCarPlayDataKeys, id: \.self) { key in
                    MultipleSelectionRow(
                        title: key.displayName,
                        isSelected: bluetoothManager.selectedCarPlayDataKeys.contains(key)
                    ) {
                        if bluetoothManager.selectedCarPlayDataKeys.contains(key) {
                            bluetoothManager.selectedCarPlayDataKeys.removeAll { $0 == key }
                        } else {
                            bluetoothManager.selectedCarPlayDataKeys.append(key)
                        }
                    }
                }
            }
            .navigationBarTitle("Select Data Keys")
            .navigationBarItems(trailing: Button("Done") {
                bluetoothManager.saveCarPlayConfiguration()
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

/// A simple multi-selection screen for picking which outputs show on CarPlay.
struct CarPlayOutputsSelectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode
    
    // We have 10 total possible channels (8 low + 2 medium).
    // For simplicity, we’ll just label them “Output 1..10”,
    // or you could do a more advanced approach if you want
    // separate listing for LC vs MC.
    let outputIndices: [Int] = Array(0..<10)
    
    var body: some View {
        NavigationView {
            List {
                ForEach(outputIndices, id: \.self) { idx in
                    MultipleSelectionRow(
                        title: "Output \(idx + 1)",
                        isSelected: bluetoothManager.selectedCarPlayOutputs.contains(idx)
                    ) {
                        if bluetoothManager.selectedCarPlayOutputs.contains(idx) {
                            bluetoothManager.selectedCarPlayOutputs.removeAll { $0 == idx }
                        } else {
                            bluetoothManager.selectedCarPlayOutputs.append(idx)
                        }
                    }
                }
            }
            .navigationBarTitle("Select Outputs")
            .navigationBarItems(trailing: Button("Done") {
                bluetoothManager.saveCarPlayConfiguration()
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

/// A helper row that toggles selection when tapped
struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            self.action()
        }) {
            HStack {
                Text(title)
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .foregroundColor(.primary)
    }
}
