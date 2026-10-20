# Status

Stand: 20.10.2026. A1 als eigenständiges natives Entwicklungsinkrement abgenommen.
SwiftUI-App und SystemSQLite3-Kern arbeiten ohne Go-Server. Datei öffnen/anlegen,
Objektliste, SQL-Einzelstatement, ausdrückliche Schreibfreigabe, begrenzte typisierte
Ergebnisse und Abbruch sind implementiert. Keine vollständige Datenbankverwaltung.

## Nachweise

- Unabhängiger QA-Review der Ursprungskommitts `1668fe4`/`acd9032` und Fix `9ca73ca`:
  keine offenen bestätigten Befunde. Fehlerhafter Dateiwechsel ließ zunächst alte
  Objekte stehen; Fix plus ViewModelregression unabhängig nachgeprüft.
- Sauberer Archivcheckout: `sh scripts/check-apple.sh` mit Kern-/App-Tests,
  macOS-Build, generischem iPad-Simulator-Build und Dokumentationsprüfung bestanden.
  Nach dem Fix zehn Swift-Tests, davon sieben Kern- und drei App-Prüfungen.
- Zusätzliche QA-Proben für ATTACH/VACUUM/PRAGMA/Extension/Batch ohne unerlaubte
  Seiteneffekte; fehlerhafte Originaldatei bytegleich erhalten.
- [Apple-CI am geprüften Fix](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39490484574)
  und [Dokumentations-CI](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39490484414)
  tatsächlich erfolgreich. Integration als `8ea3c7c`, `ec3bbe9`, `4404f91`.

## Grenzen und Fortsetzung

macOS14/iPadOS17 sind erste Deployment-Arbeitsziele; keine echten Zielgeräte oder
alten OS-Laufzeiten geprüft. Signierte Sandboxdurchsetzung und interaktiver UI-Smoke
bleiben offen (Automation-/Bildschirmrechte sowie eigener Simulatorboot eingeschränkt).
SwiftUI-ImageRenderer und echtes ViewModel wurden ohne diese Systemrechte geprüft.
Keine fremden Geräte oder Systemberechtigungen verändert, eigene Jobs/Gerät/App entfernt.

Kein Netzwerkadapter, optionaler Backendclient, Tresor, Passkey oder CloudKit-Sync.
Keine echten Zugangsdaten persistiert. Eigener Code AGPL-3.0-only; Systembibliotheken
behalten ihre Lizenzen. Nächste Produktpakete nach gemeinsamer Planung und Review.
[Handoff A1](handoffs/A1.md), [Arbeitsplan](ARBEITSPLAN.md), [Einrichtung](../EINRICHTUNG.md).
