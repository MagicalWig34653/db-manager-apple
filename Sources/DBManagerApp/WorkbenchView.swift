// SPDX-License-Identifier: AGPL-3.0-only
import DBManagerCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchView: View {
    @State private var model = WorkbenchModel()
    @State private var importing = false
    @State private var showingConnection = false
    @State private var showingNotices = false
    @State private var selectedObject: DatabaseObject.ID?
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
            #endif
        } detail: {
            WorkspaceDetail(model: model, compact: compact)
                .navigationTitle(model.fileName ?? "Arbeitsplatz")
                .toolbar { runToolbar }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure: model.error = "Die Datei konnte nicht ausgewählt werden."
            }
        }
        .sheet(isPresented: $showingConnection, onDismiss: { model.discardConnectionDraft() }) {
            ConnectionSheet(model: model) { showingConnection = false }
        }
        .sheet(isPresented: $showingNotices) {
            NoticesView { showingNotices = false }
        }
        .focusedSceneValue(\.workbench, actions)
        .onChange(of: model.fileName) { _, name in
            if name != nil { showingConnection = false }
        }
        .task {
            model.refreshLocalFiles()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DBMSyntheticDemo") {
                await model.loadSyntheticDemo()
                if ProcessInfo.processInfo.arguments.contains("-DBMDemoDetail") { compactColumn = .detail }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 540)
        #endif
    }

    private var actions: WorkbenchActions {
        WorkbenchActions(
            openFile: { importing = true },
            createLocal: { model.createLocal() },
            connectPostgres: { showingConnection = true },
            execute: { model.execute() },
            cancel: { model.operation?.cancel() },
            closeSource: { model.close() },
            showNotices: { showingNotices = true },
            canExecute: model.fileName != nil && !model.busy,
            canCancel: model.busy,
            canCloseSource: model.fileName != nil && !model.busy,
            idle: !model.busy)
    }

    @ToolbarContentBuilder private var runToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.busy {
                Button("Abbrechen", systemImage: "stop.fill") { model.operation?.cancel() }
                    .help("Laufende Operation abbrechen (⌘.)")
            }
            Button("Ausführen", systemImage: "play.fill") { model.execute() }
                .disabled(model.fileName == nil || model.busy)
                .help("SQL ausführen (⌘↩)")
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Ausführen", systemImage: "play.fill") { model.execute() }
                .disabled(model.fileName == nil || model.busy)
        }
        #endif
    }

    private var sidebar: some View {
        List(selection: $selectedObject) {
            Section("Datenquelle") {
                Picker("Quelle", selection: Binding(get: { model.source }, set: { model.changeSource($0) })) {
                    ForEach(WorkbenchModel.Source.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(model.busy)
                if let fileName = model.fileName {
                    Label(fileName, systemImage: model.source == .sqlite ? "externaldrive" : "network")
                        .font(.callout).textSelection(.enabled)
                    Button("Datenquelle schließen", systemImage: "xmark.circle") { model.close() }
                        .disabled(model.busy)
                } else if model.source == .sqlite {
                    Button("Datei öffnen …", systemImage: "folder") { importing = true }
                        .disabled(model.busy)
                    Button("Neue lokale Datei", systemImage: "plus") { model.createLocal() }
                        .disabled(model.busy)
                } else {
                    Button("Verbindung einrichten …", systemImage: "network") { showingConnection = true }
                        .disabled(model.busy)
                }
                if model.busy { ProgressView().controlSize(.small) }
                if let error = model.error, !showingConnection {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            if model.source == .sqlite && !model.localFiles.isEmpty {
                Section("Eigene Dateien") {
                    ForEach(model.localFiles, id: \.self) { url in
                        Button(url.lastPathComponent, systemImage: "doc") { model.open(url) }
                            .disabled(model.busy)
                    }
                }
            }
            Section("Tabellen und Ansichten") {
                ForEach(model.objects) { object in
                    Label(object.schema.isEmpty ? object.name : object.schema + "." + object.name,
                          systemImage: object.kind == "view" ? "eye" : "tablecells")
                        .tag(object.id)
                        .contextMenu {
                            Button("Inhalt anzeigen", systemImage: "tablecells") { show(object) }
                            Button("Name kopieren", systemImage: "doc.on.doc") { Clipboard.copy(object.name) }
                        }
                }
                if model.objects.isEmpty { Text("Keine Objekte geladen").foregroundStyle(.secondary) }
            }
            if compact {
                Section {
                    Button("SQL-Arbeitsplatz", systemImage: "terminal") { compactColumn = .detail }
                }
            }
            Section("Projekt") {
                Button("Lizenzen und Hinweise", systemImage: "doc.text") { showingNotices = true }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selectedObject) { _, id in
            guard !model.busy, let id, let object = model.objects.first(where: { $0.id == id }) else { return }
            show(object)
            selectedObject = nil  // allow selecting the same row again to re-run it
        }
        .onChange(of: model.objects) { _, objects in
            if let id = selectedObject, !objects.contains(where: { $0.id == id }) { selectedObject = nil }
        }
        .navigationTitle("DB Manager")
    }

    private func show(_ object: DatabaseObject) {
        model.show(object)
        compactColumn = .detail
    }
}

struct WorkspaceDetail: View {
    @Bindable var model: WorkbenchModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
                Label(model.source == .sqlite ? "Lokal · SQLite" : "Direkt · PostgreSQL · TLS",
                      systemImage: model.source == .sqlite ? "externaldrive" : "network")
                Spacer()
                Text(model.fileName ?? "Keine Datenquelle aktiv").foregroundStyle(.secondary).lineLimit(1)
            }
            .font(compact ? .footnote : .body)
            if !compact { Text("SQL-Arbeitsplatz").font(.title2.bold()) }
            TextEditor(text: $model.sql)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .frame(minHeight: compact ? 90 : 100, maxHeight: compact ? 140 : 180)
                .padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .disabled(model.busy)
                .accessibilityIdentifier("sqlEditor")
            HStack(spacing: 16) {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Picker("Zeilen", selection: $model.maxRows) {
                    Text("100").tag(100); Text("1.000").tag(1_000); Text("10.000").tag(10_000)
                }.fixedSize().disabled(model.busy)
            }
            Toggle("Schreibzugriffe für diese Datenquelle erlauben", isOn: $model.allowWrites)
                .disabled(model.fileName == nil || model.busy)
            limitsNote
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            if let result = model.result {
                ResultView(result: result)
            } else if !model.busy {
                ContentUnavailableView("Bereit für eine Abfrage", systemImage: "tablecells",
                                       description: Text("Eine SQLite-Datei öffnen oder direkt mit PostgreSQL verbinden. Kein Go-Server erforderlich."))
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 20)
    }

    @ViewBuilder private var limitsNote: some View {
        let text = "Eine Anweisung je Ausführung · 10 s Zeitlimit · 1 MiB je Zelle · 8 MiB Ergebnis. Änderungen wirken auf die Datenquelle. Abbruch garantiert kein Zurücknehmen; vorher sichern."
        if compact {
            DisclosureGroup("Grenzen und Hinweise") {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }.font(.caption)
        } else {
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConnectionSheet: View {
    @Bindable var model: WorkbenchModel
    let close: () -> Void
    @State private var importingCA = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Direkt mit PostgreSQL verbinden") {
                    TextField("Hostname", text: $model.host)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                    TextField("Port", text: $model.port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Datenbank", text: $model.databaseName)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Benutzer", text: $model.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Passwort (nur flüchtig)", text: $model.password)
                }
                Section("TLS") {
                    Button("CA-Datei auswählen …", systemImage: "doc.badge.plus") { importingCA = true }
                    if let name = model.caName {
                        Text("Operator-CA: " + name).font(.caption)
                        Button("Systemvertrauen verwenden") { model.caData = nil; model.caName = nil }
                    } else {
                        Text("TLS mit Hostnamenprüfung und Systemvertrauen").font(.caption)
                    }
                    Text("Kein Go-Server · keine Speicherung · pro Operation eine TLS-Verbindung").font(.caption)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .disabled(model.busy)
            .navigationTitle("PostgreSQL")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verbinden", systemImage: "network") { model.connectPostgres() }
                        .disabled(model.busy || (model.source == .postgres && model.fileName != nil))
                }
            }
            .fileImporter(isPresented: $importingCA, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url): model.selectCA(url)
                case .failure: model.error = "Die CA-Datei konnte nicht ausgewählt werden."
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}

struct NoticesView: View {
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(ThirdPartyNotices.text).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("Lizenzen und Originalhinweise")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Schließen", action: close) } }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }
}
