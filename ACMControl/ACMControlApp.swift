//
//  ACMControlApp.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import SwiftUI

@main
struct ACMControlApp: App {
//    @StateObject var bluetoothManager = BluetoothManager.shared  // or new instance, but typically shared
        
    var body: some Scene {
        WindowGroup {
            ContentView()
                .accessibilityIdentifier("acm-control-root-view")
        }
    }
}

