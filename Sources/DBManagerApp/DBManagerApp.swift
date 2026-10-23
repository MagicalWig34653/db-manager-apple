// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

@main
struct DBManagerApp: App {
    var body: some Scene {
        WindowGroup { WorkbenchView() }
            #if os(macOS)
            .defaultSize(width: 1_100, height: 720)
            .windowResizability(.contentMinSize)
            #endif
            .commands { WorkbenchCommands() }
    }
}

/// Window-specific actions published by the focused workbench window to the menu bar.
struct WorkbenchActions {
    var openFile: () -> Void
    var createLocal: () -> Void
    var connectPostgres: () -> Void
    var execute: () -> Void
    var cancel: () -> Void
    var closeSource: () -> Void
    var showNotices: () -> Void
    var canExecute: Bool
    var canCancel: Bool
    var canCloseSource: Bool
    var idle: Bool
}

private struct WorkbenchActionsKey: FocusedValueKey { typealias Value = WorkbenchActions }

extension FocusedValues {
    var workbench: WorkbenchActions? {
        get { self[WorkbenchActionsKey.self] }
        set { self[WorkbenchActionsKey.self] = newValue }
    }
}

struct WorkbenchCommands: Commands {
    @FocusedValue(\.workbench) private var actions

    var body: some Commands {
        // Cmd+N keeps its standard meaning: a new, independent workbench window.
        CommandGroup(after: .newItem) {
            Button("SQLite-Datei öffnen …", systemImage: "folder") { actions?.openFile() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions?.idle != true)
            Button("Neue lokale SQLite-Datei", systemImage: "plus") { actions?.createLocal() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions?.idle != true)
            Button("PostgreSQL-Verbindung …", systemImage: "network") { actions?.connectPostgres() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions?.idle != true)
            Divider()
            Button("Datenquelle schließen", systemImage: "xmark.circle") { actions?.closeSource() }
                .disabled(actions?.canCloseSource != true)
        }
        CommandMenu("Abfrage") {
            Button("Ausführen", systemImage: "play.fill") { actions?.execute() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions?.canExecute != true)
            Button("Abbrechen", systemImage: "stop.fill") { actions?.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(actions?.canCancel != true)
        }
        CommandGroup(replacing: .help) {
            Button("Lizenzen und Hinweise") { actions?.showNotices() }
                .disabled(actions == nil)
        }
    }
}
