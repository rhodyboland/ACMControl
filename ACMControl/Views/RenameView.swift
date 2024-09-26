//
//  RenameView.swift
//  ACMControl
//
//  Created by Rhody Boland on 26/9/2024.
//

import Foundation
import SwiftUI

struct RenameView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var currentName: String
    var onRename: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Name")) {
                    TextField("Enter new name", text: $currentName)
                        .autocapitalization(.words)
                }
                
                Section {
                    Button(action: {
                        if !currentName.trimmingCharacters(in: .whitespaces).isEmpty {
                            onRename()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Text("Save")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(currentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Rename Output")
        }
    }
}
