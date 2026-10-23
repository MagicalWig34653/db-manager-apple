# A2 – unabhängiger Erst-, Lizenz- und Fixreview

Am 23.10.2026 aus dem bereits abgeschlossenen unabhängigen QA-Review dauerhaft
gesichert. Die ursprünglichen Laufzeitprüfungen erfolgten am 20.10.2026; sie wurden
für diesen reinen Dokumentationscheckpoint nicht erneut ausgeführt. Eigener Branch
`review/a2`, Worktree `.worktrees/a2-review`, Basis Apple-main
`7e97aaef44b9cb85749e28d225e03076432c2971`.
[Autorenübergabe](A2.md), [ADR-A002](../decisions/ADR-A002-direct-postgres.md).

## Geprüfte Quellen und Urteil

Erstreview: Kern `89b26839610ab62f9062374e5d64796d02e3dbe1`, finaler Kandidat
`abaa3dc41944c333a346e6112d4cd730a5df37dc`. Gesonderte Fixnachprüfung:
`b72e62cc66fe66bbc9a02ab0e2035a40b0235947`.

Begrenzte A2-Integration freigegeben, QA-A2-01 geschlossen, keine weiteren bestätigten
A2-Findings. Der konkrete ADR-A002-Abhängigkeitspin wurde ausdrücklich akzeptiert.
A2 ist bereits in der genannten Mainbasis integriert. Dies ist keine neue
Produktänderung und keine Freigabe von Credentialpersistenz, Vault, MySQL/MariaDB,
signierter Sandbox, realen Geräten, alten OS-Versionen oder interaktiver OS-UI.

## Tatsächlicher unabhängiger Erstreview

- Sauberes HEAD-Archiv mit `sh scripts/check-apple.sh` vollständig bestanden:
  Swift-Tests, macOS-App und generischer iPad-Simulator-Build ohne Signing,
  13 exakte identische SwiftPM-/Xcode-Pins, Originalnotices und Lizenztexte in
  beiden tatsächlichen App-Bundles, LAN-Zweckdeklaration sowie Dokumentation 72/0.
  Fünf Livetests ohne Fixtureumgebung ausdrücklich übersprungen.
- Eigene drei zufällige PostgreSQL-Fixtures: sämtliche ursprünglichen 14 Core-
  und 5 Appprüfungen tatsächlich aktiv bestanden. Nicht-Superuser, verify-full
  positiv; unbekannte CA, falscher Hostname/SAN, fehlendes TLS und falsche Credentials
  negativ. Readonly vor Benutzer-SQL fixiert, Writeconsent, Einzelstatement ohne
  Teilwirkung, Präzision/NULL/Leer/Binary, Streaming-/JSONlimits und sichere Fehler.
- Laufende Serverarbeit vor Abbruch beobachtet; separater ebenfalls verifizierter
  Cancelkanal an PID/Backendstart/DB/User/zufällige Markierung gebunden. Tatsächliche
  Freigabe und Wiederverwendung, fremde Parallelsession ungestört. Geänderte
  Sessionmarkierung meldet serverseitigen Abbruch ehrlich als unbestätigt.
- SQLite erhalten; Quellen-/Fehlerwechsel, Passwortleerung, Schreibfreigabe und
  alte Objekte/Ergebnisse im ViewModel geprüft. Keine OS-Rechte oder Truststores geändert.

## Konkrete Lizenz- und Herkunftsprüfung

Keine pauschale Ableitung aus Root-Apache/NOTICE. Beide konkreten BoringSSL-LICENSE-
Dateien unabhängig von den festgelegten offiziellen Revisionen geladen und bytegleich
mit den App-Ressourcen verglichen:

- NIOssl `15e0b9e495786807272dd4891fa4bac76aa43034`, bewusst noch nicht als Release
  getaggt; offizielle Package.swift, Vendorhash und Apache-Header von ssl_lib.cc geprüft.
  BoringSSL `8eb25be6fa18d475291122887a7bccd3762ff236`, Vendorhash-Datei SHA256
  `690a041d4f35ae56fc9259b21599bf82bf10322a40f72a10a09289c05eaa26ec`.
- SwiftCrypto4.5.2 enthält separat BoringSSL
  `0226f30467f540a3f62ef48d453f93927da199b6` mit eigenem Herkunftsnachweis.
- Beide externen Original-LICENSE-Dateien SHA256
  `827c8d8fc207c2392794eef9e00fe246f9f61fdcc132556c275be3dd8c3cd97f`, Apache-2.0.
  Tatsächlich aufgelöste Checkouts gegen Pin/Notices geprüft; keine alten
  Advertising-/SSLeay-Klauselmarker in den beiden vendorten Sourcebäumen gefunden.

Historische Originalnotices bleiben unverändert. Dies ist eine konkrete
Herkunfts-/Distributionsprüfung dieses Pins, keine allgemeine Rechts- oder
Lieferkettenfreigabe und keine zusätzliche AGPL-Ausnahme.

## QA-A2-01 und unabhängige Nachprüfung

Mittlerer Datenintegritätsbefund: Foundation-Kalender lieferte tatsächlich für
PostgreSQL DATE1500-01-01 das falsche 1499-12-23; Timestamp entsprechend verschoben.
0001-01-01 BC verlor die Era und erschien als 0001-01-03. Eigene zusätzliche echte
PG-Literalprobe zeigte die falschen nativen Werte neben korrektem serverseitigem
`::text`; ausschließlich diese Zusatzprobe war rot, die ursprünglichen 19 Fälle grün.

Fix b72e62cc ersetzt die Kalenderkonversion durch begrenzte Int64-Gregorianarithmetik
und ausdrückliches BC. Negativdivision, Schaltjahrzählung, Jahresintervall und
Mikrosekundenrest auf Überlauf geprüft; keine Foundation-/Float-Kalenderkonversion,
neue Dependency oder erkennbare kopierte Drittimplementierung.

Eigenes sauberes Fixarchiv: 1.008 unabhängige Python-Datums- und 4.032 Timestampvektoren
bestanden. Nur kalenderbezogene echte TLS-PG-Prüfungen erneut ausgeführt: drei Tests,
17 DATE- und je13 Timestamp-/Timestamptz-Literale gegen Servertext, darunter die zuvor
fehlerhaften Werte, BC/AD, negative Tage/Mikrosekunden, 1582 ohne Lücke, Schaltjahre,
4713 BC, obere Serverjahre, Infinity und endliche Int64-Randnachbarn. Alle bestanden.
Unveränderte TLS-/Lifecycle-/Plattformmatrix nicht unnötig wiederholt; Fixdokumente 73/0.

## CI, Integration und Ressourcen

Die zum Fixreview noch offene native CI ist inzwischen autoritativ erfolgreich:
[exakter Fix](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396485),
[Fixdokumentation](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39503396416).
Auch [integriertes Main](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39505094304)
erfolgreich; für diesen Checkpoint am 23.10.2026 erneut abgefragt.

Alle damaligen eigenen Archive, Scratchverzeichnisse und Fixturecontainer entfernt;
keine App/Simulator gestartet, keine eigenen Jobs offen. Dieser Reviewcheckpoint
ändert ausschließlich diese Datei. Dokumentations-/Diffprüfung bestanden.
