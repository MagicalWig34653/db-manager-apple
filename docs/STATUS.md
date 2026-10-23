# Status

Stand: 23.10.2026. Einziger autorisierter Fortsetzungsrahmen: bis heute
10:00 Europe/Berlin (=08:00 UTC), Agents implementieren und prüfen; Root koordiniert.

 A1 und A2 nach unabhängiger QA und exakter erfolgreicher CI
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
  bestätigt. Keine offenen bestätigten A2-Befunde. [Handoff A2](handoffs/A2.md),
  [dauerhaft gesicherter unabhängiger Review](handoffs/A2-review.md).
- Autorenprüfung: 17 Kern-/5 Appprüfungen mit drei echten TLS-/Negativfixtures
  aktiv bestanden, zusätzliche frische Mac-/iPad-Builds einschließlich Originaltexte
  und Info.plist. Ohne Fixtureumgebung überspringt Standardswifttest sechs Livetests;
  das ist kein zusätzlicher Live-Nachweis.
- [Apple-CI am exakten letzten Fix](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396485)
  und [Dokumentations-CI](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396416)
  erfolgreich. Beide früheren A2-CI-Paare ebenfalls erfolgreich. [Kombinierte Main-CI auf 7e97aae](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39505094304)
  inzwischen tatsächlich erfolgreich, exakten Commit und Ergebnis erneut geprüft. Lokale Leadintegration bestanden:
  Swift-Testlauf mit ausdrücklich sechs übersprungenen Livetests, 1.008/4.032
  Kalendervektoren, 13 Pins/Originalnotices einschließlich tatsächlicher Checkouts
  und Dokumentation74/0. Kein neuer Live-/Geräte- oder Appbuildnachweis daraus.
- [ADR-A002](decisions/ADR-A002-direct-postgres.md) akzeptiert den konkreten
  unveröffentlichten offiziellen NIOssl-Revisionspin mit belegtem Apache-BoringSSL-
  Originaltext. 13 gepinnte Abhängigkeiten, identische SwiftPM-/Xcode-Locks und
  Originalnotices im Appbundle; fehlendes Release-Tag bleibt Wartungsrisiko.

## Eigenständiger Tresorkern S2a

Nach unabhängigem [Core-/Securityreview](handoffs/S2a-review.md) ohne offene
Findings als **isoliertes Core-Inkrement** zur Integration abgenommen. Kein
produktiver Anchor, keine App-/Credentialpersistenzfreigabe. [Paketvertrag und
Originaltexte](../Packages/DBManagerVault/README.md), [ADR-A003](decisions/ADR-A003-vault-core.md),
[Autoren-/Integrationshandoff](handoffs/S2a.md). Gesamtes Paket bytegleich zum
geprüften Stand8d6fa37 einschließlich Codebbbc4e6 übernommen; vorhandene App-,
Root-Package-, Xcode- und A2-Produktdateien unverändert.

Kombinierte lokale Releaseprüfung bestanden: 16 Vaulttests, sechs echte abrupte
Prozessabbrüche, iPad-Simulator-Zielcompile, Format-/Fixture-/14-Argon2hashes.
Zusätzlich bestehende A2-App mit17 Kern-/5 Appprüfungen (sechs Livetests ohne
Fixtures ausdrücklich übersprungen), 1.008 Datum-/4.032 Timestampvektoren,
13 Abhängigkeitspins/Originalnotices, macOS-/iPad-Appbuild einschließlich
Originaltexte und Info.plist; Dokumentation125/0 am geprüften Integrationsbaum.
Keine erneute tatsächliche PostgreSQL-Liveprüfung oder Gerätelaufzeit behauptet.
Neue kombinierte Main-CI nach Veröffentlichung vor endgültigem CI-Checkpoint prüfen.

Der Anker ist eine zwingende externe Vertrauensannahme, kein produktiver
InMemory-/Dateifallback. Reservierungen vor Verschlüsselung, CAS/Pending/Rootbudget,
private POSIX-Modi und Hash-Rücklesen sind geprüft; keine Hardwaremonotonie,
ACL-/Sandbox-/FileProtection-/Restorefreigabe. Spätere S2b-App-/Ankerschritte
benötigen gesonderte Plattformprobe und unabhängige Abnahme. Aktuell darf nur ein
enger S2b-Plattformvorschlag vorbereitet werden; keine Appsecretpersistierung.

## Grenzen und Fortsetzung

macOS14/iPadOS17 sind Deploymentziele, keine nachgewiesenen alten Laufzeiten.
Echte Geräte, Signing-/Sandboxdurchsetzung, Distribution und interaktiver OS-UI-Smoke
bleiben offen. NSLocalNetworkUsageDescription ist Zweckdeklaration, keine erteilte
Berechtigung. Keine fremden Geräte/Container oder Systemrechte verändert.
Keine nativen MySQL-/MariaDB-Adapter wegen belegtem TLS-Downgrade, kein SSH,
HTTP-Backendclient, produktiver Tresor, Passkey, CloudKit-Sync oder Teamumfang.
Abbruch garantiert keinen Rollback, READ ONLY keine vollständige DB-Sandbox.
Eigener Code AGPL-3.0-only, Abhängigkeiten behalten ihre Original-Lizenzen.

Nächster Schritt: kombinierte S2a-Main-CI kontrollieren und S2b-Plattformgate
mit tatsächlichen Signierungs-/Nichtinteraktionsgrenzen abstimmen. [Arbeitsplan](ARBEITSPLAN.md),
[Einrichtung](../EINRICHTUNG.md). Apple-Statuspflege ist für dieses Fortsetzungsfenster an den S2a-Agent delegiert.
