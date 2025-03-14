//
//  CarPlaySceneDelegate.swift
//  ACMControl
//
//  Created by Rhody Boland on 13/3/2025.
//


import CarPlay
import UIKit
import os.log

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    // MARK: - CarPlay Interface
    
    /// Interface controller for managing CarPlay templates
    var interfaceController: CPInterfaceController?
    
    /// A logger for debugging (optional)
    private let logger = Logger(subsystem: "com.example.ACMControl", category: "CarPlay")
    
    // MARK: - Templates
    
    private var dataListTemplate: CPListTemplate?
    private var controlListTemplate: CPListTemplate?
    private var tabBarTemplate: CPTabBarTemplate?
    
    // MARK: - Timer for Automatic Refresh
    
    private var refreshTimer: Timer?
    
    // MARK: - Bluetooth Manager (Singleton)
    
    let bluetoothManager = BluetoothManager.shared
    
    // MARK: - Required CarPlay Lifecycle Methods
    
    /// Called when CarPlay connects and the scene is ready to display content.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        logger.info("CarPlay connected. Setting up templates.")
        
        // Create the two main list templates
        dataListTemplate = createDataListTemplate()
        controlListTemplate = createControlListTemplate()
        
        // Combine them into a CPTabBarTemplate
        if let dataTemplate = dataListTemplate,
           let controlTemplate = controlListTemplate {
            
            tabBarTemplate = CPTabBarTemplate(templates: [dataTemplate, controlTemplate])
//            tabBarTemplate?.title = "ACM"
            
            // Set the tab bar as the root template
            interfaceController.setRootTemplate(tabBarTemplate!, animated: true, completion: nil)
        }
        
        // Start a refresh timer to update data every 10s
        startRefreshTimer()
    }
    
    /// Called when CarPlay disconnects. Clean up references and timers.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        logger.info("CarPlay disconnected. Cleaning up.")
        
        // Stop refreshing
        stopRefreshTimer()
        
        // Clear references
        self.interfaceController = nil
        self.dataListTemplate = nil
        self.controlListTemplate = nil
        self.tabBarTemplate = nil
    }
    
    // MARK: - Creating the Data Template
    
    private func createDataListTemplate() -> CPListTemplate {
        let items   = carPlayDataItems()
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "ACM Data", sections: [section])
        
        // Appearance in the tab bar
        template.tabTitle = "Data"
        template.tabImage = UIImage(systemName: "waveform.path.ecg") // SF Symbol
        
        return template
    }
    
    /// Builds CPListItems for each user-selected data key (from BluetoothManager).
    private func carPlayDataItems() -> [CPListItem] {
        let keys = bluetoothManager.selectedCarPlayDataKeys
        
        return keys.map { dataKey in
            let title = dataKey.displayName
            let value = bluetoothManager.getCarPlayValue(for: dataKey)
            let item  = CPListItem(text: title, detailText: value)
            
            // You can add a tap handler if you want deeper detail:
            item.handler = { [weak self] _, completion in
                self?.logger.info("Tapped \(title) list item in CarPlay.")
                completion()
            }
            return item
        }
    }
    
    // MARK: - Creating the Control Template
    
    private func createControlListTemplate() -> CPListTemplate {
        let items   = carPlayControlItems()
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "ACM Controls", sections: [section])
        
        // Appearance in the tab bar
        template.tabTitle = "Controls"
        template.tabImage = UIImage(systemName: "switch.2")
        
        return template
    }
    
    /// Builds CPListItems for the user-selected outputs.
    /// Tapping toggles the relevant output on/off via BluetoothManager.
    private func carPlayControlItems() -> [CPListItem] {
        let selectedIndices = bluetoothManager.selectedCarPlayOutputs
        
        return selectedIndices.map { idx -> CPListItem in
            let isLC = (idx < 8)
            let localIndex = isLC ? idx : (idx - 8)
            print("Refreshing States")
            // Determine current ON/OFF status
            let isOn = isLC
                ? bluetoothManager.lowCurrentStates[localIndex]
                : bluetoothManager.mediumCurrentStates[localIndex]
            
            // Output name
            let title = isLC
                ? bluetoothManager.lowCurrentOutputNames[localIndex]
                : bluetoothManager.mediumCurrentOutputNames[localIndex]
            
            // Show ON/OFF in detail
            let detailText = isOn ? "ON" : "OFF"
            
            let item = CPListItem(text: title, detailText: detailText)
            item.handler = { [weak self] _, completion in
                guard let self = self else {
                    completion()
                    return
                }
                // Toggle the channel
                if isLC {
                    self.bluetoothManager.setLowCurrentState(index: localIndex, state: !isOn)
                } else {
                    self.bluetoothManager.setMediumCurrentState(index: localIndex, state: !isOn)
                }
                
                // Refresh the detail text after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.reloadControlTemplate()
                }
                completion()
            }
            return item
        }
    }

    
    // MARK: - Reloading the Templates
    
    /// Refresh both the data and control templates. Called by the refresh timer.
    private func reloadCarPlayTemplates() {
        reloadDataTemplate()
        reloadControlTemplate()
    }
    
    private func reloadDataTemplate() {
        guard let dataListTemplate = dataListTemplate else { return }
        let items = carPlayDataItems()
        let section = CPListSection(items: items)
        dataListTemplate.updateSections([section])
    }
    
    private func reloadControlTemplate() {
        guard let controlListTemplate = controlListTemplate else { return }
        let items = carPlayControlItems()
        let section = CPListSection(items: items)
        controlListTemplate.updateSections([section])
    }
    
    // MARK: - Timer for Automatic Refresh
    
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true,
            block: { [weak self] _ in
                self?.logger.info("Refreshing CarPlay templates...")
                self?.reloadCarPlayTemplates()
            }
        )
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
