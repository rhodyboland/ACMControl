//
//  GradientUtility.swift
//  ACMControl
//
//  Created by Rhody Boland on 27/9/2024.
//

import Foundation
import SwiftUI

struct GradientUtility {
    static func gradientForState(_ state: String) -> LinearGradient {
        switch state {
        case "Fault":
            return LinearGradient(
                gradient: Gradient(colors: [Color.red, Color.orange]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "Off", "Bulk", "Absorption", "Float", "Equalize (Manual)", "Starting-up", "Auto Equalize / Recondition", "External Control":
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
