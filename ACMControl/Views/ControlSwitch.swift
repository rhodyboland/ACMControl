//
//  ControlSwitch.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct ControlSwitch: View {
    @Binding var title: String
    @Binding var isOn: Bool
    var brightness: Binding<Float>?
    var index: Int
    var isAlwaysOn: Bool = false  // <--- new property
    var action: () -> Void
    var renameAction: () -> Void
    var brightnessAdjustAction: (() -> Void)?
    
    // A computed var for whether we show the "on" gradient
    private var effectiveIsOn: Bool {
        return isOn || isAlwaysOn
    }
    
    var body: some View {
        // We'll disable the button if it's always on
        Button(action: {
            // If always on, ignore taps (no toggle)
            guard !isAlwaysOn else { return }
            
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isOn.toggle()
            }
            print("\(title) toggled to \(isOn ? "ON" : "OFF")")
            action()
        }) {
            HStack {
                Image(systemName: "power")
                    .foregroundColor(effectiveIsOn ? .white : .gray)
                    .font(.headline)
                    .padding(.leading, 10)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(effectiveIsOn ? .white : .primary)
                    .padding(.leading, 5)
                
                Spacer()
            }
            .padding()
            .background(
                ZStack {
                    if effectiveIsOn {
                        // Normal "on" gradient, but reduce opacity if always-on
                        LinearGradient(gradient: Gradient(colors: [Color.green, Color.mint]),
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                            .opacity(isAlwaysOn ? 0.6 : 1.0) // "grey out" if forced ON
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .cornerRadius(12)
            .shadow(color: effectiveIsOn ? Color.green.opacity(0.4) : Color.black.opacity(0.1),
                    radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if brightness != nil {
                Button(action: { brightnessAdjustAction?() }) {
                    Label("Adjust Brightness", systemImage: "slider.horizontal.3")
                }
            }
            Button(action: { renameAction() }) {
                Label("Rename", systemImage: "pencil")
            }
        }
    }
}


struct InverterControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    // A computed var for whether we show the "on" gradient
    private var effectiveIsOn: Bool {
        switch bluetoothManager.inverterState {
        case .on:
            return true
        case .off, .error:
            return false
        }
    }
    var body: some View {
        Button(action: {
            // If currently ON => user wants OFF
            // If OFF or ERROR => user tries to turn it ON
            switch bluetoothManager.inverterState {
            case .on:
                bluetoothManager.setInverterState(on: false)
            case .off, .error:
                bluetoothManager.setInverterState(on: true)
            }
        
        }) {
            HStack {
                Image(systemName: "power")
                    .foregroundColor(effectiveIsOn ? .white : .gray)
                    .font(.headline)
                    .padding(.leading, 10)
                
                Text("Inverter")
                    .font(.headline)
                    .foregroundColor(effectiveIsOn ? .white : .primary)
                    .padding(.leading, 5)
                
                Spacer()
            }
            .padding()
            // Use a background gradient that matches the other controls
            .background(gradientForInverterState(bluetoothManager.inverterState))
            .cornerRadius(12)
            .shadow(color: shadowColor(for: bluetoothManager.inverterState), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Gradients for Off/On/Error
    private func gradientForInverterState(_ state: InverterState) -> LinearGradient {
        switch state {
        case .off:
            // Gray gradient to match "Off"
            return LinearGradient(
                gradient: Gradient(colors: [Color(UIColor.systemGray6), Color(UIColor.systemGray6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .on:
            // Green gradient to match "On" (like LC on)
            return LinearGradient(
                gradient: Gradient(colors: [Color.green, Color.mint]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .error:
            // Red/orange for "Error"
            return LinearGradient(
                gradient: Gradient(colors: [Color.red, Color.orange]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Shadow color
    private func shadowColor(for state: InverterState) -> Color {
        switch state {
        case .off:
            return Color.black.opacity(0.1)
        case .on:
            return Color.green.opacity(0.4)
        case .error:
            return Color.red.opacity(0.4)
        }
    }
}
