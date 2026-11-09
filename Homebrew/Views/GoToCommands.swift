//
//  GoToCommands.swift
//  Homebrew
//

import SwiftUI

extension FocusedValues {
    @Entry var goToPresented: Binding<Bool>?
}

/// View → Go to… (⌘K): one field that reaches any page, installed package or catalogue package.
struct GoToCommands: Commands {
    @FocusedValue(\.goToPresented) private var isPresented

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(String(localized: "Go to…", bundle: #bundle, comment: "View menu: open the Go to palette")) {
                isPresented?.wrappedValue = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(isPresented == nil)
        }
    }
}
