// SPDX-License-Identifier: AGPL-3.0-only
import DBManagerCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct DBManagerApp: App {
    var body: some Scene {
        WindowGroup { WorkbenchView() }
    }
}

@MainActor
@Observable
final class WorkbenchModel {
    let database = SQLiteDatabase()
    private let localRoot: URL?
    var fileName: String?
    var objects: [DatabaseObject] = []
    var localFiles: [URL] = []
    var sql = "SELECT sqlite_version() AS SQLite, 9223372036854775807 AS Ganzzahl, NULL AS Leerwert"
    var result: QueryResult?
    var error: String?
    var busy = false
    var allowWrites = false
    var maxRows = 1_000
    var operation: Task<Void, Never>?

    init(localRoot: URL? = nil) { self.localRoot = localRoot }

    private func localDirectory() throws -> URL {
        let directory = try localRoot ?? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("DBManager", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func refreshLocalFiles() {
        guard let directory = try? localDirectory() else { return }
        localFiles = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "sqlite" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func open(_ url: URL, create: Bool = false) {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        fileName = nil; objects = []; allowWrites = false
        operation = Task {
            defer { busy = false; operation = nil }
            await database.close()
            do {
                try await database.open(url, create: create)
                let loadedObjects = try await database.objects()
                fileName = url.lastPathComponent
                objects = loadedObjects
                refreshLocalFiles()
            } catch {
                await database.close()
                fileName = nil; objects = []; result = nil; allowWrites = false
                self.error = error.localizedDescription
            }
        }
    }

    func createLocal() {
        do {
            let directory = try localDirectory()
            open(directory.appendingPathComponent("Datenbank-\(UUID().uuidString.prefix(8)).sqlite"), create: true)
        } catch { self.error = "Die lokale Datei konnte nicht angelegt werden." }
    }

    func execute() {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        let statement = sql
        let writes = allowWrites
        let limit = maxRows
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                result = try await database.execute(statement, allowWrites: writes, limits: QueryLimits(maxRows: limit))
                objects = try await database.objects()
            } catch { self.error = error.localizedDescription }
        }
    }

    func show(_ object: DatabaseObject) {
        sql = SQLiteDatabase.selectSQL(for: object.name)
        execute()
    }

    func close() {
        guard !busy else { return }
        busy = true
        operation = Task {
            await database.close()
            fileName = nil; objects = []; result = nil; allowWrites = false
            busy = false; operation = nil
        }
    }
}

struct WorkbenchView: View {
    @State private var model = WorkbenchModel()
    @State private var importing = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Lokale SQLite-Datei") {
                    Button("Datei öffnen …", systemImage: "folder") { importing = true }
                    Button("Neue lokale Datei", systemImage: "plus") { model.createLocal() }
                    if let fileName = model.fileName {
                        Label(fileName, systemImage: "externaldrive")
                            .font(.caption).textSelection(.enabled)
                        Button("Datei schließen", systemImage: "xmark.circle") { model.close() }
                    }
                }.disabled(model.busy)
                Section("Eigene Dateien") {
                    ForEach(model.localFiles, id: \.self) { url in
                        Button(url.lastPathComponent) { model.open(url) }.disabled(model.busy)
                    }
                }
                Section("Tabellen und Ansichten") {
                    ForEach(model.objects) { object in
                        Button { model.show(object) } label: {
                            Label(object.name, systemImage: object.kind == "view" ? "eye" : "tablecells")
                        }.disabled(model.busy)
                    }
                    if model.objects.isEmpty { Text("Keine Objekte geladen").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("DB Manager")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Lokal · SQLite", systemImage: "desktopcomputer")
                    Spacer()
                    Text(model.fileName ?? "Keine Datei geöffnet").foregroundStyle(.secondary).lineLimit(1)
                }
                Text("SQL-Arbeitsplatz").font(.title2.bold())
                TextEditor(text: $model.sql)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 180)
                    .padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(model.busy)
                    .accessibilityIdentifier("sqlEditor")
                HStack(spacing: 16) {
                    Button("Ausführen", systemImage: "play.fill") { model.execute() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.fileName == nil || model.busy)
                        .keyboardShortcut(.return, modifiers: .command)
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Button("Abbrechen", systemImage: "stop.fill") { model.operation?.cancel() }
                    }
                    Spacer()
                    Picker("Zeilen", selection: $model.maxRows) {
                        Text("100").tag(100); Text("1.000").tag(1_000); Text("10.000").tag(10_000)
                    }.fixedSize().disabled(model.busy)
                }
                Toggle("Schreibzugriffe für diese Datei erlauben", isOn: $model.allowWrites)
                    .disabled(model.fileName == nil || model.busy)
                Text("Eine Anweisung je Ausführung · 10 s Zeitlimit · 1 MiB je Zelle · 8 MiB Ergebnis. Änderungen wirken direkt auf die Datei; vorher sichern.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
                if let result = model.result {
                    ResultView(result: result)
                } else if !model.busy {
                    ContentUnavailableView("Bereit für eine Abfrage", systemImage: "tablecells",
                                           description: Text("Eine Datei öffnen oder anlegen und SQL ausführen. Die App arbeitet ohne Server."))
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Arbeitsplatz")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure: model.error = "Die Datei konnte nicht ausgewählt werden."
            }
        }
        .task { model.refreshLocalFiles() }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}

struct ResultView: View {
    let result: QueryResult
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(result.rows.count) Zeilen · \(result.durationMS) ms").font(.headline)
                if let affected = result.rowsAffected { Text("Änderungen: \(affected)") }
                if result.truncated { Label("Zeilengrenze erreicht", systemImage: "ellipsis.circle").foregroundStyle(.orange) }
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
                            Text(column.name).font(.system(.caption, design: .monospaced).bold())
                                .frame(width: 190, alignment: .leading).padding(8)
                        }
                    }.background(.quaternary)
                    ForEach(result.rows.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(result.rows[index].indices, id: \.self) { column in
                                let cell = result.rows[index][column]
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(cell.kind == .null ? "NULL" : (cell.value == "" ? "\"\"" : String((cell.value ?? "").prefix(500))))
                                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    Text(cell.kind.rawValue + ((cell.value?.count ?? 0) > 500 ? " · Vorschau gekürzt" : ""))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }.frame(width: 190, alignment: .leading).padding(8)
                            }
                        }
                        Divider()
                    }
                }
            }.frame(minHeight: 120)
        }
    }
}
