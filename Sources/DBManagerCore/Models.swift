// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public struct Cell: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case null, text, integer, float, binary, decimal, boolean, timestamp }
    public let kind: Kind
    public let value: String?
    public init(kind: Kind, value: String? = nil) { self.kind = kind; self.value = value }
}

public struct Column: Codable, Sendable, Equatable {
    public let name: String
    public let databaseType: String
    enum CodingKeys: String, CodingKey { case name; case databaseType = "database_type" }
}

public struct QueryResult: Codable, Sendable {
    public let columns: [Column]
    public let rows: [[Cell]]
    public let rowsAffected: String?
    public let truncated: Bool
    public let durationMS: Int
    enum CodingKeys: String, CodingKey {
        case columns, rows, truncated
        case rowsAffected = "rows_affected", durationMS = "duration_ms"
    }
}

public struct DatabaseObject: Sendable, Identifiable, Hashable {
    public let name: String
    public let kind: String
    public let schema: String
    public init(name: String, kind: String, schema: String = "") { self.name = name; self.kind = kind; self.schema = schema }
    public var id: String { schema + "\0" + kind + "\0" + name }
}

public struct QueryLimits: Sendable {
    public let maxRows: Int
    public let maxCellBytes: Int
    public let maxResultBytes: Int
    public let timeout: TimeInterval
    public init(maxRows: Int = 1_000, maxCellBytes: Int = 1_048_576,
                maxResultBytes: Int = 8_388_608, timeout: TimeInterval = 10) {
        self.maxRows = maxRows; self.maxCellBytes = maxCellBytes
        self.maxResultBytes = maxResultBytes; self.timeout = timeout
    }
}

public enum DatabaseError: Error, LocalizedError, Sendable, Equatable {
    case notOpen, cannotOpen, invalidLimits, emptySQL, multipleStatements, writesDisabled
    case canceled, busy, resultTooLarge, invalidText, queryFailed(Int32)
    case invalidConnection, connectionFailed, postgresFailed, operationInProgress, cancellationUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .notOpen: "Zuerst eine Datenquelle öffnen oder verbinden."
        case .cannotOpen: "Die SQLite-Datei konnte nicht geöffnet werden. Dateizugriff prüfen."
        case .invalidLimits: "Die Abfragegrenzen sind ungültig."
        case .emptySQL: "Eine SQL-Anweisung eingeben."
        case .multipleStatements: "Genau eine SQL-Anweisung ausführen; nachfolgende Kommentare separat entfernen."
        case .writesDisabled: "Schreibzugriffe sind gesperrt. Zum Ändern ausdrücklich freigeben."
        case .canceled: "Abfrage abgebrochen oder Zeitlimit erreicht. Bereits erfolgte Änderungen bleiben möglich."
        case .busy: "Die Datei ist gesperrt. Später erneut versuchen."
        case .resultTooLarge: "Zell- oder Ergebnisgröße überschreitet die Grenze. Abfrage eingrenzen."
        case .invalidText: "Das Ergebnis enthält Text ohne gültige UTF-8-Darstellung. Als BLOB abfragen."
        case .cancellationUnconfirmed: "Abbruch angefordert und lokale Verbindung geschlossen; serverseitiger Abbruch nicht bestätigt. Änderungen und laufende Arbeit bleiben möglich."
        case .invalidConnection: "Die PostgreSQL-Verbindungswerte oder CA-Datei sind ungültig."
        case .connectionFailed: "PostgreSQL-Verbindung fehlgeschlagen. Ziel, TLS-Zertifikat und Anmeldung prüfen."
        case .postgresFailed: "PostgreSQL-Anweisung fehlgeschlagen. Syntax, Berechtigungen und Lesemodus prüfen."
        case .operationInProgress: "Es läuft bereits eine Datenbankoperation."
        case .queryFailed(let code): "SQL fehlgeschlagen (SQLite-Code \(code)). Syntax und Datenbank prüfen."
        }
    }
}
