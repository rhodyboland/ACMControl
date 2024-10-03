//
//  DataModels.swift
//  ACMControl
//
//  Created by Rhody Boland on 27/9/2024.
//

import Foundation
import Combine

enum DataCardType {
    case standard
    case batteryPercentage
    // Add more cases as needed for future card types
}

struct DataItem: Identifiable {
    let id = UUID()
    let title: String
    var value: String
    var state: String
    var isDisabled: Bool
    let type: DataCardType
    
    // Initializer with default type as .standard
    init(title: String, value: String, state: String, isDisabled: Bool, type: DataCardType = .standard) {
        self.title = title
        self.value = value
        self.state = state
        self.isDisabled = isDisabled
        self.type = type
    }
}

class Subsystem: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var state: String
    @Published var dataItems: [DataItem]

    init(name: String, state: String, dataItems: [DataItem]) {
        self.name = name
        self.state = state
        self.dataItems = dataItems
    }
}
