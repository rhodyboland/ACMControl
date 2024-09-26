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
    var brightness: Binding<Float>?
    var index: Int
    var action: () -> Void
    var renameAction: () -> Void
    var brightnessAdjustAction: (() -> Void)?
    
    // MARK: - Body
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isOn.toggle()
            }
            print("\(title) toggled to \(isOn ? "ON" : "OFF")")
            action()
        }) {
            HStack {
                if isOn {
                    Image(systemName: "power")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.leading, 10)
                } else {
                    Image(systemName: "power")
                        .foregroundColor(.gray)
                        .font(.headline)
                        .padding(.leading, 10)
                }
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(isOn ? .white : .primary)
                    .padding(.leading, 5)
                
                Spacer()
                
            }
            .padding()
            .background(
                ZStack {
                    if isOn {
                        LinearGradient(gradient: Gradient(colors: [Color.green, Color.mint]),
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .cornerRadius(12)
            .shadow(color: isOn ? Color.green.opacity(0.4) : Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
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
