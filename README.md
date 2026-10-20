# db-manager-apple

Eigenständige Swift/SwiftUI-App für macOS und iPadOS. Eigener Projektcode: **AGPL-3.0-only**.

Erster nativer Arbeitsplatz: lokale SQLite-Dateien öffnen oder anlegen, Tabellen
und Ansichten auswählen sowie einzelne SQL-Anweisungen ausführen. SwiftUI und
SystemSQLite3 arbeiten vollständig ohne Go-Server. Erste Arbeitsziele sind
macOS 14 und iPadOS 17; echte Altgeräte-/iPadtests sind noch offen.

Schreibzugriffe sind zunächst gesperrt und müssen bewusst freigegeben werden.
Ergebnisse unterscheiden NULL, leere Strings und BLOBs, erhalten 64-Bit-Ganzzahlen
und zeigen Zeilenkürzung ausdrücklich. Zeilen-, Byte- und Zeitgrenzen begrenzen
Abfragen; Abbruch kann bereits erfolgte Datenbankänderungen nicht zurücknehmen.
Keine phpMyAdmin-Paritäts-, Netzwerk-, Tresor- oder Syncfreigabe.

Gemeinsame Anforderungen liegen im [Hauptprojekt](https://github.com/MagicalWig34653/db-manager).
Die lokale App implementiert keinen Backend-HTTP-Client.

- [Agent-Einstieg](AGENTS.md), [Claude Code](CLAUDE.md)
- [Status](docs/STATUS.md), [Arbeitsplan](docs/ARBEITSPLAN.md)
- [Einrichtung](EINRICHTUNG.md), [Lizenz](LICENSE)
- [Native Architekturentscheidung](docs/decisions/ADR-A001-native-sqlite.md), [A1-Handoff](docs/handoffs/A1.md)
