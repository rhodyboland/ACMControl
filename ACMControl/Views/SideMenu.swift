//
//  SideMenu.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct SideMenu: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text("ACM Control")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 100)
                .padding(.bottom, 20)
            
            // Configuration Option
            NavigationLink(destination: ConfigurationView(bluetoothManager: bluetoothManager)) {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                    Text("Configuration")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 10)
            }
            
            // About Option
            NavigationLink(destination: AboutView()) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 10)
            }
            
            Spacer()
            
            // Version Info
            Text("ACM Control v1.0")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 30)
        .frame(width: UIScreen.main.bounds.width * 0.75, alignment: .leading)
        .background(Color(.systemBackground))
        .edgesIgnoringSafeArea(.all)
    }
}
