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
                // ---- Existing Sections (Voltage Config, Channels, etc.) remain unchanged ----
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
                
                // ---- New Section for CarPlay configuration ----
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
    }
}

/// A simple multi-selection screen for picking data keys.
struct CarPlayDataSelectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode
    
    var allKeys: [CarPlayDataKey] = CarPlayDataKey.allCases
    
    var body: some View {
        NavigationView {
            List {
                ForEach(allKeys, id: \.self) { key in
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
