# db-manager-apple

Eigenständige Swift/SwiftUI-App für macOS und iPadOS. Eigener Projektcode: **AGPL-3.0-only**.

Native Arbeitsplätze: lokale SQLite-Dateien öffnen/anlegen oder direkt über
verifiziertes TLS mit PostgreSQL verbinden, Objekte auswählen und einzelne SQL-
Anweisungen ausführen. SQLite bleibt ohne Netzwerk und Go-Server verfügbar. Erste Arbeitsziele sind
macOS 14 und iPadOS 17; echte Altgeräte-/iPadtests sind noch offen.

Schreibzugriffe sind zunächst gesperrt und müssen bewusst freigegeben werden.
Ergebnisse unterscheiden NULL, leere Strings und BLOBs, erhalten 64-Bit-Ganzzahlen
und zeigen Zeilenkürzung ausdrücklich. Zeilen-, Byte- und Zeitgrenzen begrenzen
Abfragen; Abbruch kann bereits erfolgte Datenbankänderungen nicht zurücknehmen.
PostgreSQL erhält zusätzlich exakte Decimal-, Boolean- und Zeitwerte. Credentials
bleiben flüchtig; TLS ist verpflichtend. Noch keine vollständige Verwaltungs-,
MySQL-/MariaDB-, Tresor-, Sync- oder Distributionsfreigabe. A2 steht vor unabhängiger QA.

Gemeinsame Anforderungen liegen im [Hauptprojekt](https://github.com/MagicalWig34653/db-manager).
Die lokale App implementiert keinen Backend-HTTP-Client.

- [Agent-Einstieg](AGENTS.md), [Claude Code](CLAUDE.md)
- [Status](docs/STATUS.md), [Arbeitsplan](docs/ARBEITSPLAN.md)
- [Einrichtung](EINRICHTUNG.md), [Lizenz](LICENSE)
- [Direkter PostgreSQL-Pfad](docs/decisions/ADR-A002-direct-postgres.md), [A2-Handoff](docs/handoffs/A2.md)
- [Native Architekturentscheidung](docs/decisions/ADR-A001-native-sqlite.md), [A1-Handoff](docs/handoffs/A1.md)
