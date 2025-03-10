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
        if let percentage = Double(state.replacingOccurrences(of: "%", with: "")) {
            return gradientForBatteryPercentage(percentage)
        }

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
    
    static func gradientForBatteryPercentage(_ percentage: Double) -> LinearGradient {
            let clampedPercentage = max(0, min(100, percentage))  // Clamp to valid range
            
            let gradient: Gradient
            
            switch clampedPercentage {
            case 0...20:
                gradient = Gradient(colors: [Color.red, Color.orange]) // Critical Low
            case 21...40:
                gradient = Gradient(colors: [Color.orange, Color.yellow]) // Low
            case 41...60:
                gradient = Gradient(colors: [Color.yellow, Color.green]) // Mid
            case 61...80:
                gradient = Gradient(colors: [Color.green, Color.mint]) // High
            default:
                gradient = Gradient(colors: [Color.green, Color.mint]) // Full
            }
            
            return LinearGradient(
                gradient: gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
