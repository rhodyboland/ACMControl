//
//  ControlSwitch.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct ControlSwitch: View {
    // MARK: - Properties
    @Binding var title: String
    @Binding var isOn: Bool
    var brightness: Binding<Float>? // Optional brightness binding for LC switches
    var index: Int
    var action: () -> Void
    var renameAction: () -> Void
    var brightnessAdjustAction: (() -> Void)?
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .onChange(of: isOn) { newValue in
                        print("\(title) toggled to \(newValue ? "ON" : "OFF")")
                        action()
                    }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .contextMenu {
            if brightness != nil {
                Button(action: {
                    brightnessAdjustAction?()
                }) {
                    Label("Adjust Brightness", systemImage: "slider.horizontal.3")
                }
            }
            Button(action: {
                renameAction()
            }) {
                Label("Rename", systemImage: "pencil")
            }
        }
    }
}
