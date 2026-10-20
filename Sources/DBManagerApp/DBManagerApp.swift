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
    enum Source: String, CaseIterable, Identifiable { case sqlite = "SQLite", postgres = "PostgreSQL"; var id: Self { self } }
    let database = SQLiteDatabase()
    let postgres = PostgresDatabase()
    var source: Source = .sqlite
    var host = ""
    var port = "5432"
    var databaseName = ""
    var username = ""
    var password = ""
    var caData: Data?
    var caName: String?
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

    private func clearActive() {
        fileName = nil; objects = []; result = nil; allowWrites = false; error = nil
    }

    func changeSource(_ next: Source) {
        guard !busy, next != source else { return }
        source = next; clearActive(); password = ""; caData = nil; caName = nil
        sql = next == .sqlite ? "SELECT sqlite_version() AS SQLite" : "SELECT version() AS PostgreSQL"
        busy = true
        operation = Task {
            await database.close(); await postgres.close()
            busy = false; operation = nil
        }
    }

    func selectCA(_ url: URL) {
        guard source == .postgres, !busy, fileName == nil else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 1_048_577), !data.isEmpty,
                  data.count <= 1_048_576 else { throw DatabaseError.invalidConnection }
            caData = data; caName = url.lastPathComponent; error = nil
        } catch { caData = nil; caName = nil; self.error = "Die CA-Datei konnte nicht gelesen werden (höchstens 1 MiB)." }
    }

    func connectPostgres() {
        guard source == .postgres, !busy else { return }
        clearActive(); busy = true
        let settings = PostgresSettings(host: host, port: Int(port) ?? 0, database: databaseName,
                                        username: username, password: password, certificateAuthority: caData)
        let label = host + "/" + databaseName
        password = ""
        operation = Task {
            defer { busy = false; operation = nil }
            await database.close(); await postgres.close()
            do {
                let loaded = try await postgres.open(settings)
                try Task.checkCancellation()
                fileName = label; objects = loaded
            } catch {
                await postgres.close(); clearActive()
                self.error = (error as? DatabaseError)?.localizedDescription ?? DatabaseError.canceled.localizedDescription
            }
        }
    }

    func open(_ url: URL, create: Bool = false) {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        if source != .sqlite { sql = "SELECT sqlite_version() AS SQLite" }
        source = .sqlite; password = ""
        fileName = nil; objects = []; allowWrites = false
        operation = Task {
            defer { busy = false; operation = nil }
            await database.close(); await postgres.close()
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
                if source == .sqlite {
                    result = try await database.execute(statement, allowWrites: writes, limits: QueryLimits(maxRows: limit))
                    objects = try await database.objects()
                } else {
                    result = try await postgres.execute(statement, allowWrites: writes, limits: QueryLimits(maxRows: limit))
                    objects = try await postgres.objects()
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func show(_ object: DatabaseObject) {
        sql = source == .sqlite ? SQLiteDatabase.selectSQL(for: object.name) : PostgresDatabase.selectSQL(for: object)
        execute()
    }

    func close() {
        guard !busy else { return }
        busy = true; clearActive(); password = ""
        operation = Task {
            await postgres.close(); await database.close()
            fileName = nil; objects = []; result = nil; allowWrites = false
            busy = false; operation = nil
        }
    }
}

struct WorkbenchView: View {
    @State private var model = WorkbenchModel()
    @State private var importing = false
    @State private var importingCA = false
    @State private var showingNotices = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Datenquelle") {
                    Picker("Quelle", selection: Binding(get: { model.source }, set: { model.changeSource($0) })) {
                        ForEach(WorkbenchModel.Source.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(model.busy)
                }
                if model.source == .postgres {
                    Section("Direkt mit PostgreSQL verbinden") {
                        Group {
                        TextField("Hostname", text: $model.host)
                            .autocorrectionDisabled()
                        TextField("Port", text: $model.port)
                        TextField("Datenbank", text: $model.databaseName)
                            .autocorrectionDisabled()
                        TextField("Benutzer", text: $model.username)
                            .autocorrectionDisabled()
                        SecureField("Passwort (nur flüchtig)", text: $model.password)
                        Button("CA-Datei auswählen …") { importingCA = true }
                        if let name = model.caName {
                            Text("Operator-CA: " + name).font(.caption)
                            Button("Systemvertrauen verwenden") { model.caData = nil; model.caName = nil }
                        } else { Text("TLS mit Hostnamenprüfung und Systemvertrauen").font(.caption) }
                        }.disabled(model.fileName != nil)
                        Button("Verbinden", systemImage: "network") { model.connectPostgres() }.disabled(model.fileName != nil)
                        if model.fileName != nil { Button("Verbindungseinstellungen verwerfen") { model.close() } }
                        Text("Kein Go-Server · keine Speicherung · pro Operation eine TLS-Verbindung").font(.caption)
                    }.disabled(model.busy)
                }
                if model.source == .sqlite {
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
                }
                Section("Tabellen und Ansichten") {
                    ForEach(model.objects) { object in
                        Button { model.show(object) } label: {
                            Label(object.schema.isEmpty ? object.name : object.schema + "." + object.name, systemImage: object.kind == "view" ? "eye" : "tablecells")
                        }.disabled(model.busy)
                    }
                    if model.objects.isEmpty { Text("Keine Objekte geladen").foregroundStyle(.secondary) }
                }
                Section("Projekt") {
                    Button("Lizenzen und Hinweise") { showingNotices = true }
                }
            }
            .navigationTitle("DB Manager")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(model.source == .sqlite ? "Lokal · SQLite" : "Direkt · PostgreSQL · TLS", systemImage: "desktopcomputer")
                    Spacer()
                    Text(model.fileName ?? "Keine Datenquelle aktiv").foregroundStyle(.secondary).lineLimit(1)
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
                Toggle("Schreibzugriffe für diese Datenquelle erlauben", isOn: $model.allowWrites)
                    .disabled(model.fileName == nil || model.busy)
                Text("Eine Anweisung je Ausführung · 10 s Zeitlimit · 1 MiB je Zelle · 8 MiB Ergebnis. Änderungen wirken auf die Datenquelle. Abbruch garantiert kein Zurücknehmen; vorher sichern.")
                    .font(.caption).foregroundStyle(.secondary)
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
            .padding(20)
            .navigationTitle("Arbeitsplatz")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure: model.error = "Die Datei konnte nicht ausgewählt werden."
            }
        }
        .fileImporter(isPresented: $importingCA, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.selectCA(url)
            case .failure: model.error = "Die CA-Datei konnte nicht ausgewählt werden."
            }
        }
        .sheet(isPresented: $showingNotices) {
            VStack {
                HStack { Text("Lizenzen und Originalhinweise").font(.headline); Spacer(); Button("Schließen") { showingNotices = false } }
                ScrollView { Text(ThirdPartyNotices.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding().frame(minWidth: 400, minHeight: 400)
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
