//
//  DataView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import SwiftUI

// MARK: - DataCard
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

// MARK: - BatteryPercentageCard
struct BatteryPercentageCard: View {
    var title: String
    var percentage: Int // 0..100
    var backgroundColor: LinearGradient
    var disabled: Bool = false
    
    @State private var animatedPercentage: Double = 0.0
    
    var body: some View {
        VStack {
            // GeometryReader for the semi-circle & text overlay
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height * 2)
                ZStack {
                    // Background semi-circle
                    SemiCircle()
                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    
                    // Gradient foreground arc
                    AngularGradient(
                        gradient: Gradient(colors: [Color.red, Color.yellow, Color.green]),
                        center: .center,
                        startAngle: .degrees(170),
                        endAngle: .degrees(370)
                    )
                    .mask(
                        SemiCircle(progress: animatedPercentage / 100)
                            .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    )
                    .animation(.easeOut(duration: 1.0), value: animatedPercentage)
                    
                    // Percentage Text
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
            .frame(height: 120) // Visual size for the semi-circle
            
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

// MARK: - SemiCircle shape for BatteryPercentageCard
struct SemiCircle: Shape {
    var progress: Double = 1.0 // from 0.0..1.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Arc from 170 degrees to (170 + 200*progress) degrees
        let startAngle = Angle(degrees: 170)
        let endAngle   = Angle(degrees: 170 + (200.0 * progress))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: rect.width / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}

// MARK: - DataView
struct DataView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @State private var selectedSubsystem: Subsystem? = nil
    
    // 2-column grid
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    // The two main subsystems
    var subsystems: [Subsystem] {
        [
            bluetoothManager.batterySubsystem,
            bluetoothManager.solarSubsystem
        ]
    }
    
    var body: some View {
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
                    }
                }
            }
            .padding()
        }
        // Use sheet with an Identifiable object
        .sheet(item: $selectedSubsystem) { subsystem in
            SubsystemDetailView(subsystem: subsystem)
        }
    }
}

// MARK: - SubsystemDetailView
struct SubsystemDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var subsystem: Subsystem
    
    let standardGridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Show battery card first if it exists
                    if let batteryCard = subsystem.dataItems.first(where: { $0.type == .batteryPercentage }) {
                        let rawString = batteryCard.value.replacingOccurrences(of: "%", with: "")
                        // e.g. "75.23"
                        
                        let floatVal = Float(rawString) ?? 0.0
                        // Now floatVal is 75.23
                        
                        BatteryPercentageCard(
                            title: batteryCard.title,
                            percentage: Int(floatVal.rounded()), // e.g. 75
                            backgroundColor: GradientUtility.gradientForState(batteryCard.state),
                            disabled: batteryCard.isDisabled
                        )
                    }

                    
                    // Standard data cards
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
