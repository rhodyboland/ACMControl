//
//  BrightnessAdjusterView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct BrightnessAdjusterView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var lightName: String
    @Binding var brightness: Float
    var onChange: (Float) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Adjust Brightness")) {
                    Slider(value: $brightness, in: 0...1, step: 0.01, onEditingChanged: { editing in
                        if !editing {
                            // Handle brightness change completion
                            print("\(lightName) brightness set to \(Int(brightness * 100))%")
                            onChange(brightness)
                        }
                    })
                    .accentColor(.blue)
                    
                    Text("\(Int(brightness * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Brightness Adjuster")
            .navigationBarItems(trailing:
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}
