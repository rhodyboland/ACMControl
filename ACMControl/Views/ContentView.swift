//
//  ContentView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import SwiftUI

struct ContentView: View {
    @StateObject var bluetoothManager = BluetoothManager()
    
    // Side Menu State
    @State private var isShowingSideMenu = false
    
    // Brightness Adjuster State
    @State private var selectedBrightnessIndex: Int? = nil
    @State private var showBrightnessAdjuster: Bool = false
    
    // Rename Sheet State
    @State private var selectedRenameIndex: Int? = nil
    @State private var renameType: RenameType? = nil
    @State private var showRenameSheet: Bool = false
    @State private var newName: String = ""
    
    // Enum to differentiate between LC and MC for renaming
    enum RenameType {
        case lowCurrent
        case mediumCurrent
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .leading) {
                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        Text("ACM Control")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.top)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Connection Status
                        HStack {
                            if bluetoothManager.isConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connected")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Disconnected")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // Data View
                        DataView(bluetoothManager: bluetoothManager)
                        
                        // Low Current (LC) Control Switches
                        LowCurrentControlView(
                            bluetoothManager: bluetoothManager,
                            selectedRenameIndex: $selectedRenameIndex,
                            renameType: $renameType,
                            newName: $newName,
                            showRenameSheet: $showRenameSheet,
                            selectedBrightnessIndex: $selectedBrightnessIndex,
                            showBrightnessAdjuster: $showBrightnessAdjuster
                        )
                        
                        // Medium Current (MC) Control Switches
                        MediumCurrentControlView(
                            bluetoothManager: bluetoothManager,
                            selectedRenameIndex: $selectedRenameIndex,
                            renameType: $renameType,
                            newName: $newName,
                            showRenameSheet: $showRenameSheet
                        )
                        
                        Spacer()
                    }
                    .padding()
                }
                .disabled(isShowingSideMenu) // Disable interaction when side menu is open
                
                // Semi-transparent Overlay when Side Menu is Open
                if isShowingSideMenu {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                isShowingSideMenu = false
                            }
                        }
                }
                
                // Side Menu
                SideMenu(bluetoothManager: bluetoothManager, isShowing: $isShowingSideMenu)
                    .frame(width: UIScreen.main.bounds.width * 0.75) // 75% of screen width
                    .offset(x: isShowingSideMenu ? 0 : -UIScreen.main.bounds.width * 0.75)
                    .animation(.easeInOut(duration: 0.3), value: isShowingSideMenu)
            }
            .navigationBarItems(leading:
                Button(action: {
                    withAnimation {
                        self.isShowingSideMenu.toggle()
                    }
                }) {
                    Image(systemName: "line.horizontal.3")
                        .imageScale(.large)
                        .padding()
                }
            )
//            .navigationBarTitle("ACM Control", displayMode: .inline)
            // Brightness Adjuster Sheet
            .sheet(isPresented: $showBrightnessAdjuster) {
                if let index = selectedBrightnessIndex {
                    BrightnessAdjusterView(
                        lightName: Binding(
                            get: { bluetoothManager.lowCurrentOutputNames[index] },
                            set: { newValue in
                                bluetoothManager.lowCurrentOutputNames[index] = newValue
                                bluetoothManager.saveOutputNames()
                            }
                        ),
                        brightness: Binding(
                            get: { bluetoothManager.lowCurrentBrightness[index] },
                            set: { newValue in
                                bluetoothManager.lowCurrentBrightness[index] = newValue
                            }
                        ),
                        onChange: { newBrightness in
                            // Send brightness to ESP32
                            print("Brightness for LC\(index + 1) set to \(Int(newBrightness * 100))%")
                            // Example command: "B1xx" where xx is brightness in hex
                            let brightnessHex = String(format: "%02X", Int(newBrightness * 255))
                            let command = "B\(index + 1)\(brightnessHex)"
                            bluetoothManager.controlAccessory(command: command)
                        }
                    )
                }
            }
            // Rename Sheet
            .sheet(isPresented: $showRenameSheet) {
                if let index = selectedRenameIndex, let type = renameType {
                    RenameView(
                        currentName: $newName,
                        onRename: {
                            if type == .lowCurrent {
                                bluetoothManager.renameLowCurrentOutput(at: index, to: newName)
                            } else if type == .mediumCurrent {
                                bluetoothManager.renameMediumCurrentOutput(at: index, to: newName)
                            }
                            newName = ""
                        }
                    )
                }
            }
        }
    }
}

struct LowCurrentControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var selectedRenameIndex: Int?
    @Binding var renameType: ContentView.RenameType?
    @Binding var newName: String
    @Binding var showRenameSheet: Bool
    @Binding var selectedBrightnessIndex: Int?
    @Binding var showBrightnessAdjuster: Bool

    private let lcColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Low Current Outputs")
                .font(.headline)
                .padding(.leading)

            LazyVGrid(columns: lcColumns, spacing: 16) {
                ForEach(0..<8) { index in
                    ControlSwitch(
                        title: Binding(
                            get: { bluetoothManager.lowCurrentOutputNames[index] },
                            set: { newValue in
                                bluetoothManager.lowCurrentOutputNames[index] = newValue
                                bluetoothManager.saveOutputNames()
                            }
                        ),
                        isOn: Binding(
                            get: { bluetoothManager.lowCurrentStates[index] },
                            set: { newValue in
                                bluetoothManager.lowCurrentStates[index] = newValue
                                // Optionally, send the state change to BluetoothManager here
                            }
                        ),
                        brightness: Binding(
                            get: { bluetoothManager.lowCurrentBrightness[index] },
                            set: { newValue in
                                bluetoothManager.lowCurrentBrightness[index] = newValue
                            }
                        ),
                        index: index,
                        action: {
                            bluetoothManager.setLowCurrentState(index: index, state: bluetoothManager.lowCurrentStates[index])
                        },
                        renameAction: {
                            // Set rename parameters and show sheet
                            selectedRenameIndex = index
                            renameType = .lowCurrent
                            newName = bluetoothManager.lowCurrentOutputNames[index]
                            showRenameSheet = true
                        },
                        brightnessAdjustAction: {
                            // Set brightness parameters and show sheet
                            selectedBrightnessIndex = index
                            showBrightnessAdjuster = true
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}


struct MediumCurrentControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var selectedRenameIndex: Int?
    @Binding var renameType: ContentView.RenameType?
    @Binding var newName: String
    @Binding var showRenameSheet: Bool

    private let mcColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medium Current Outputs")
                .font(.headline)
                .padding(.leading)

            LazyVGrid(columns: mcColumns, spacing: 16) {
                ForEach(0..<2) { index in
                    ControlSwitch(
                        title: Binding(
                            get: { bluetoothManager.mediumCurrentOutputNames[index] },
                            set: { newValue in
                                bluetoothManager.mediumCurrentOutputNames[index] = newValue
                                bluetoothManager.saveOutputNames()
                            }
                        ),
                        isOn: Binding(
                            get: { bluetoothManager.mediumCurrentStates[index] },
                            set: { newValue in
                                bluetoothManager.mediumCurrentStates[index] = newValue
                                // Optionally, send the state change to BluetoothManager here
                            }
                        ),
                        brightness: nil, // No brightness for MC switches
                        index: index,
                        action: {
                            bluetoothManager.setMediumCurrentState(index: index, state: bluetoothManager.mediumCurrentStates[index])
                        },
                        renameAction: {
                            // Set rename parameters and show sheet
                            selectedRenameIndex = index
                            renameType = .mediumCurrent
                            newName = bluetoothManager.mediumCurrentOutputNames[index]
                            showRenameSheet = true
                        },
                        brightnessAdjustAction: nil // No brightness for MC switches
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}
