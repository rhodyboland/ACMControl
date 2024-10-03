//
//  DataView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct DataView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var selectedSubsystem: Subsystem?
    @State private var isSheetPresented: Bool = false
    
    // Define grid layout with 2 columns
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    // Gather all subsystems into an array
    var subsystems: [Subsystem] {
        [
            bluetoothManager.batterySubsystem,
            bluetoothManager.solarSubsystem
            // Add more subsystems here
        ]
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(subsystems) { subsystem in
                        DataCard(
                            title: subsystem.name,
                            value: subsystem.state,
                            backgroundColor: GradientUtility.gradientForState(subsystem.state),
                            disabled: false
                        )
                        .onTapGesture {
                            selectedSubsystem = subsystem
                            isSheetPresented = true
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $isSheetPresented) {
            if let subsystem = selectedSubsystem {
                SubsystemDetailView(subsystem: subsystem)
            }
        }
    }
}

// MARK: - DataCard View
struct DataCard: View {
    var title: String
    var value: String
    var backgroundColor: LinearGradient
    var disabled: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .accessibility(addTraits: .isHeader)
            Spacer()
            Text(value)
                .font(.title2)
                .foregroundColor(.white)
                .accessibilityLabel(value)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .opacity(disabled ? 0.5 : 1.0)
    }
}


struct SubsystemDetailView: View {
    
    let subsystem: Subsystem
    @Environment(\.presentationMode) var presentationMode
    
    // Define grid layout with 2 columns for standard cards
    let standardGridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Render BatteryPercentageCard first if it exists
                    if let batteryCard = subsystem.dataItems.first(where: { $0.type == .batteryPercentage }) {
                        BatteryPercentageCard(
                            title: batteryCard.title,
                            percentage: Int(batteryCard.value.replacingOccurrences(of: "%", with: "")) ?? 0,
                            backgroundColor: GradientUtility.gradientForState(batteryCard.state),
                            disabled: batteryCard.isDisabled
                        )
                        .padding(.bottom, 12) // Spacing after full-width card
                    }
                    
                    // Filter out the batteryPercentage card from standard cards
                    let standardCards = subsystem.dataItems.filter { $0.type != .batteryPercentage }
                    
                    LazyVGrid(columns: standardGridColumns, spacing: 12) {
                        ForEach(standardCards) { item in
                            DataCard(
                                title: item.title,
                                value: item.value,
                                backgroundColor: GradientUtility.gradientForState(item.state),
                                disabled: item.isDisabled
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(subsystem.name)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct BatteryPercentageCard: View {
    var title: String
    var percentage: Int // Value between 0 to 100
    var backgroundColor: LinearGradient
    var disabled: Bool = false
    
    @State private var animatedPercentage: Double = 0.0
    
    var body: some View {
        VStack {

            // GeometryReader to handle the semi-circle and percentage text
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height * 2)
                ZStack {
                    // Background Semi-Circle
                    SemiCircle()
                        .stroke(Color.gray.opacity(0.3),style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    
                    // Gradient Foreground Semi-Circle
                    AngularGradient(
                        gradient: Gradient(colors: [Color.red, Color.yellow, Color.green]),
                        center: .center,
                        startAngle: .degrees(170),
                        endAngle: .degrees(170 + 200)
                    )
                    .mask(
                        SemiCircle(progress: animatedPercentage / 100)
                            .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    )
                    .animation(.easeOut(duration: 1.0), value: animatedPercentage)
                    
                    // Percentage Text Centered Within the Semi-Circle
                    Text("\(percentage)%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 15)
                        .accessibilityLabel("\(percentage) percent battery")
                }
                .frame(width: size, height: size / 2)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2.5)
            }
            .padding(.top, 10)
            .frame(height: 120) // Increased height for better display
            // Title Text
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .accessibility(addTraits: .isHeader)

        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .opacity(disabled ? 0.5 : 1.0)
        .onAppear {
            animatedPercentage = Double(percentage)
        }
        .onChange(of: percentage) { newValue in
            animatedPercentage = Double(newValue)
        }
    }
}

struct SemiCircle: Shape {
    var progress: Double = 1.0 // Progress from 0.0 to 1.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Start at 180 degrees (left) and end at 0 degrees (right) based on progress
        let startAngle = Angle(degrees: 170)
        let endAngle = Angle(degrees: 170+(200 * progress))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: rect.width / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}

protocol DataCardProtocol: View {
    var title: String { get }
    var backgroundColor: LinearGradient { get }
    var disabled: Bool { get }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let bluetoothManager = BluetoothManager()
        DataView(bluetoothManager: bluetoothManager)
    }
}
