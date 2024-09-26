//
//  AboutView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About This App")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 20)
            
            Text("ACM Control is designed to manage the Accessory Control Module (ACM) for 4WD and overlanding vehicles. It allows you to control various outputs, monitor inputs, and configure settings to ensure optimal performance and reliability.")
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Version 1.0.0")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGray6))
        .cornerRadius(15)
        .shadow(radius: 10)
        .padding()
    }
}
