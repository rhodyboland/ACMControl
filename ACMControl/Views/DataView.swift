//
//  DataView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct DataView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    // Define grid layout with 3 columns
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    // Existing DataCards
                    DataCard(
                        title: "Battery Voltage",
                        value: "\(String(format: "%.2f", bluetoothManager.batteryVoltage)) V",
                        backgroundColor: gradientForState("Normal"),
                        disabled: false
                    )
                    DataCard(
                        title: "Current Usage",
                        value: "\(String(format: "%.2f", bluetoothManager.currentUsage)) A",
                        backgroundColor: gradientForState("Normal"),
                        disabled: false
                    )
                    DataCard(
                        title: "Solar Voltage",
                        value: "\(String(format: "%.2f", bluetoothManager.solarVoltage)) V",
                        backgroundColor: gradientForState("Normal"),
                        disabled: !bluetoothManager.serialState
                    )
                    DataCard(
                        title: "Solar Current",
                        value: "\(String(format: "%.2f", bluetoothManager.solarCurrent)) A",
                        backgroundColor: gradientForState("Normal"),
                        disabled: !bluetoothManager.serialState
                    )
                    DataCard(
                        title: "Solar Power",
                        value: "\(String(format: "%.2f", bluetoothManager.solarPower)) W",
                        backgroundColor: gradientForState("Normal"),
                        disabled: !bluetoothManager.serialState
                    )
                    DataCard(
                        title: "Solar State",
                        value: bluetoothManager.solarChargingState,
                        backgroundColor: gradientForState(bluetoothManager.solarChargingState),
                        disabled: !bluetoothManager.serialState
                    )
                    
                    // Continue adding as needed
                }
                .padding()
            }
            
        }
    }
    
    func gradientForState(_ state: String) -> LinearGradient {
        switch state {
        case "Fault":
            return LinearGradient(gradient: Gradient(colors: [Color.red, Color.orange]),
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing)
        case "Off", "Bulk", "Absorption", "Float", "Equalize (Manual)", "Starting-up", "Auto Equalize / Recondition", "External Control":
            return LinearGradient(gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing)
        default:
            return LinearGradient(gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing)
        }
    }
}




// MARK: - DataCard View
struct DataCard: View {
    var title: String
    var value: String
    var backgroundColor: LinearGradient
    var disabled: Bool = false // Existing parameter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.title2)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100) // Fixed height
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .opacity(disabled ? 0.5 : 1.0) // Existing opacity handling
    }
}
