// SPDX-License-Identifier: AGPL-3.0-only
import DBManagerCore
import SwiftUI
import UniformTypeIdentifiers

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


extension WorkbenchModel {
    /// Display text of one result cell; long values are previewed only.
    static func displayText(_ cell: Cell, limit: Int = 500) -> String {
        switch cell.kind {
        case .null: return "NULL"
        default:
            guard let value = cell.value else { return "NULL" }
            return value.isEmpty ? "\"\"" : String(value.prefix(limit))
        }
    }

    /// Complete value for copying (not the truncated preview).
    static func fullText(_ cell: Cell) -> String { cell.kind == .null ? "NULL" : (cell.value ?? "NULL") }

    static func displayNote(_ cell: Cell, limit: Int = 500) -> String {
        cell.kind.rawValue + ((cell.value?.count ?? 0) > limit ? " · Vorschau gekürzt" : "")
    }

    #if DEBUG
    /// Debug-only helper for simulator screenshots: synthetic data, never compiled into Release.
    func loadSyntheticDemo() async {
        guard fileName == nil else { return }
        createLocal()
        await operation?.value
        guard error == nil else { return }
        allowWrites = true
        sql = """
        CREATE TABLE kunden(id INTEGER PRIMARY KEY, name TEXT, stadt TEXT, umsatz REAL, notiz TEXT);
        """
        execute(); await operation?.value
        for (index, row) in [("Beispiel GmbH", "Hamburg", 1250.5), ("Muster AG", "München", 980.0),
                             ("Demo e.K.", "Köln", 15.25), ("Test KG", "Berlin", 4400.0)].enumerated() {
            sql = "INSERT INTO kunden VALUES (\(index + 1), '\(row.0)', '\(row.1)', \(row.2), NULL)"
            execute(); await operation?.value
        }
        allowWrites = false
        sql = "SELECT * FROM kunden ORDER BY id"
        execute(); await operation?.value
    }
    #endif
}
