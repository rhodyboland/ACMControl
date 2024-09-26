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

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Voltage Configuration")) {
                    HStack {
                        Text("Cut Out Voltage")
                        Spacer()
                        TextField("12.0", value: $bluetoothManager.cutOutVoltage, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Cut In Voltage")
                        Spacer()
                        TextField("12.4", value: $bluetoothManager.cutInVoltage, format: .number)
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
