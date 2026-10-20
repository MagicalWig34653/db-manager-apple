# Status

Stand: 20.10.2026. A1 und A2 nach unabhängiger QA und exakter erfolgreicher CI
im Apple-main integriert. Eigenständiger nativer SwiftUI-Arbeitsplatz ohne Go.
Lokales SQLite und direktes PostgreSQL: Katalog, Einzelstatement, ausdrückliche
Schreibfreigabe, begrenzte typisierte Ergebnisse und Abbruch. Zugangsdaten nur im
Arbeitsspeicher; keine vollständige Datenbankverwaltung oder Credentialpersistenz.

## Nachweise und Entscheidungen

- A1: zehn Swift-Tests, Mac-/generischer iPad-Simulator-Build und unabhängige
  Sicherheits-/Lifecycleprüfungen bestanden; Dateiwechselfix geschlossen.
  Integration `8ea3c7c`/`ec3bbe9`/`4404f91`. [Handoff A1](handoffs/A1.md).
- A2: Quellen `89b2683`/`abaa3dc`/`b72e62c`, integriert als
  `fdd533e`/`cd5d886`/`031b1e8`. Direkte PostgresNIO-Verbindung mit verpflichtendem
  verify-full-TLS, separatem ebenfalls verifiziertem und an eigene Sessionidentität
  gebundenem Abbruchkanal. Readonly durch DB-Transaktion und vorherigen eigenen
  SELECT, begrenztes Streaming, genaue Decimal-/Integer-/Kalenderdarstellung.
- Vollständiger unabhängiger A2-Review und gesonderte Fixnachprüfung bestanden.
  QA-A2-01 verfälschte historische proleptische Daten und BC/AD; Fix unabhängig
  mit 1.008 Datum-/4.032 Timestampvektoren sowie drei echten TLS-PG-Kalenderfällen
  bestätigt. Keine offenen bestätigten A2-Befunde. [Handoff A2](handoffs/A2.md).
- Autorenprüfung: 17 Kern-/5 Appprüfungen mit drei echten TLS-/Negativfixtures
  aktiv bestanden, zusätzliche frische Mac-/iPad-Builds einschließlich Originaltexte
  und Info.plist. Ohne Fixtureumgebung überspringt Standardswifttest sechs Livetests;
  das ist kein zusätzlicher Live-Nachweis.
- [Apple-CI am exakten letzten Fix](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396485)
  und [Dokumentations-CI](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396416)
  erfolgreich. Beide früheren A2-CI-Paare ebenfalls erfolgreich. Kombinierte Main-CI
  nach Veröffentlichung separat kontrollieren. Lokale Leadintegration bestanden:
  Swift-Testlauf mit ausdrücklich sechs übersprungenen Livetests, 1.008/4.032
  Kalendervektoren, 13 Pins/Originalnotices einschließlich tatsächlicher Checkouts
  und Dokumentation74/0. Kein neuer Live-/Geräte- oder Appbuildnachweis daraus.
- [ADR-A002](decisions/ADR-A002-direct-postgres.md) akzeptiert den konkreten
  unveröffentlichten offiziellen NIOssl-Revisionspin mit belegtem Apache-BoringSSL-
  Originaltext. 13 gepinnte Abhängigkeiten, identische SwiftPM-/Xcode-Locks und
  Originalnotices im Appbundle; fehlendes Release-Tag bleibt Wartungsrisiko.

## Aktive Arbeit S2a

Security-/Apple-Agent arbeitet in `.worktrees/vault-core`, `feat/vault-core`, Basis
`7cbeb38`. Ausschließlich neues eigenständiges Packages/DBManagerVault, eigene Tests/
Fixtures/Originaltexte/CI/Skripte, ADR-A003/Sicherheitsdokumente/Handoff. Keine App-/
Xcode-/Rootpackage-/A2- oder zentralen Statusdateien. S1-Format aus Hauptrepo ist
abgenommen, noch keine Produktpersistenz. Geplant sind Actor-Session, sichere atomare
lokale Ablage, externer CAS-/Nutzungsanker und Recovery mit neuen Faktoren; unabhängige
Core-QA und echte produktive Anchorintegration bleiben getrennte Gates.

## Grenzen und Fortsetzung

macOS14/iPadOS17 sind Deploymentziele, keine nachgewiesenen alten Laufzeiten.
Echte Geräte, Signing-/Sandboxdurchsetzung, Distribution und interaktiver OS-UI-Smoke
bleiben offen. NSLocalNetworkUsageDescription ist Zweckdeklaration, keine erteilte
Berechtigung. Keine fremden Geräte/Container oder Systemrechte verändert.
Keine nativen MySQL-/MariaDB-Adapter wegen belegtem TLS-Downgrade, kein SSH,
HTTP-Backendclient, produktiver Tresor, Passkey, CloudKit-Sync oder Teamumfang.
Abbruch garantiert keinen Rollback, READ ONLY keine vollständige DB-Sandbox.
Eigener Code AGPL-3.0-only, Abhängigkeiten behalten ihre Original-Lizenzen.

Nächster Schritt: Leadintegrationsprüfung und neue Main-CI kontrollieren, S2a nach
Autorenabschluss unabhängig prüfen. [Arbeitsplan](ARBEITSPLAN.md),
[Einrichtung](../EINRICHTUNG.md). Zentrale Statusdateien gehören dem Lead.
