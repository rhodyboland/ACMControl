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
    
    // Define grid layout with 2 columns
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            DataCard(title: "Battery Voltage", value: "\(String(format: "%.2f", bluetoothManager.batteryVoltage)) V")
            DataCard(title: "Current Usage", value: "\(String(format: "%.2f", bluetoothManager.currentUsage)) A")
            DataCard(title: "Solar Voltage", value: "\(String(format: "%.2f", bluetoothManager.solarVoltage)) V")
            DataCard(title: "Solar Current", value: "\(String(format: "%.2f", bluetoothManager.solarCurrent)) A")
            DataCard(title: "Solar Power", value: "\(String(format: "%.2f", bluetoothManager.solarPower)) W")
            DataCard(title: "Solar Charging", value: bluetoothManager.solarCharging ? "Yes" : "No")
        }
        .padding()
    }
}

// MARK: - DataCard View
struct DataCard: View {
    var title: String
    var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(value)
                .font(.title2)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]),
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
