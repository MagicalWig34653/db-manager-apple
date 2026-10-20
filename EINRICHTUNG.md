# Einrichtung

Voraussetzungen: macOS mit Xcode 26.3/Swift 6.2 oder neuer, installiertem iOS-Simulator-SDK
sowie Python 3 für die Dokumentationsprüfung. Lokal geprüft: Xcode 27.1,
Swift 6.4, macOS-/iOS-SDK 27.0 auf Apple Silicon. Keine globale Toolinstallation,
feste externe Swift-Pakete laut `Package.resolved`; kein Go-Server erforderlich.
Für den ersten Build ist Zugriff auf die gepinnten offiziellen Quellrepositories nötig.

## Reproduzierbare Prüfung

```sh
sh scripts/check-apple.sh
```

Das Skript legt ein eigenes temporäres Buildverzeichnis an, führt Swift-Tests,
macOS- und iPad-Simulator-Build aus und entfernt sein Buildverzeichnis danach.
Signing ist dabei deaktiviert; der Simulator wird weder gestartet noch gestoppt.
Ein Build mit Deploymentziel 14/17 belegt keinen Lauf auf diesen OS-Versionen.

Einzelbefehle, jeweils mit selbst gewähltem temporärem Buildverzeichnis:

```sh
swift test --scratch-path /tmp/dbmanager-swift-check -j 4
xcodebuild -project DBManager.xcodeproj -scheme DBManager \
  -destination 'platform=macOS' -derivedDataPath /tmp/dbmanager-mac-check \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project DBManager.xcodeproj -scheme DBManager \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/dbmanager-ipad-check \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-docs.py
```

Temporäre Verzeichnisse vermeiden den in dieser Umgebung beobachteten Xcode-
Codesignfehler durch Finder-Metadaten bei Ausgaben im synchronisierten Workspace.
Keine privaten Zertifikate oder globalen Berechtigungen zum Umgehen ändern.
`swift build` baut auch das macOS-Executable; für ein App-Bundle das Xcode-Projekt
verwenden. `Package.resolved` und der Xcode-Lock binden denselben Graphen einschließlich
einer festen offiziellen NIOssl-Revision; keine bewegliche Branchbindung.

## Anwendung

`DBManager.xcodeproj` öffnen, Schema `DBManager` und eigenen Mac oder iPad-Simulator
wählen. Für echtes Gerät oder Verteilung eigenes Signing konfigurieren; dieser
Auftrag veröffentlicht keine signierte App. Xcode enthält für macOS die deklarierte
App-Sandbox, Dateiauswahlberechtigung und ausgehende Netzwerkberechtigung. Unsigned Builds beweisen deren Laufzeit-
Durchsetzung nicht.

„Neue lokale Datei“ legt eine SQLite-Datei im eigenen Application-Support-Verzeichnis
an; sie erscheint nach Neustart unter „Eigene Dateien“. „Datei öffnen …“ wählt eine
vorhandene lokale SQLite-Datei. Externe Auswahlberechtigungen bleiben nur für die
aktuelle Öffnung erhalten; keine Bookmarks oder SQL-Historie werden gespeichert.
Dateiauswahl akzeptiert allgemeine Datendateien, SQLite prüft deren Nutzbarkeit.
Vor Änderungen eine eigene Sicherung erstellen. Auf Dateiprovidern/iCloud-Drive
oder bei fremden WAL-Schreibern ist kein sicherer gemeinsamer Schreibbetrieb
nachgewiesen; zunächst lokale, exklusiv verwendete Kopien nutzen.

Eine SQL-Anweisung je Ausführung; nachfolgende Kommentare hinter dem ersten
Semikolon werden ebenfalls abgewiesen. Schreibzugriffe müssen bewusst aktiviert
sein. Tabellen-/Ansichtsabfragen bleiben durch die gewählte Zeilengrenze begrenzt;
die Navigation verweigert übergroße Kataloge statt sie still zu kürzen.
`ATTACH`, `DETACH`, `VACUUM INTO`, Erweiterungsladen und nicht freigegebene PRAGMAs
werden verweigert. Die erste Stufe ist kein vollständiger SQLite-Administrationsclient.

Höchstens 10.000 Zeilen, standardmäßig 1.000, 1 MiB je Zelle und 8 MiB begrenzte
Ergebnisdarstellung; Zeitlimit in der UI 10 Sekunden. Lange Zellen zeigt die UI
als gekennzeichnete 500-Zeichen-Vorschau. Ein Bytefehler liefert kein scheinbar
vollständiges Teilergebnis. „Abbrechen“ und Zeitlimit verwenden SQLite-Progress-
Callbacks; bei Dateisperren wird spätestens nach etwa 200 ms ein Busyfehler
geliefert. Das ist keine harte Echtzeitgarantie bei blockiertem Dateisystem/I/O.

## Direktes PostgreSQL

Quelle „PostgreSQL“ wählen, Hostname, Port, Datenbank, Benutzer und Passwort
eingeben. Standardmäßig gilt das Systemvertrauen. Für private/testweise CAs eine
PEM-Datei über „CA-Datei auswählen …“ ausdrücklich auswählen (höchstens 1 MiB);
diese Wurzeln ersetzen nur für diese Verbindung das Standardvertrauen. Host und
Zertifikat müssen zusammenpassen. Es gibt keinen unsicheren TLS-Fallback und
keine Änderung von Keychain/Systemtruststore. „Verbinden“ prüft den Katalog und
leert danach das Passwortfeld; interne Einstellungen bleiben nur im Arbeitsspeicher.
Für LAN-Ziele kann das Betriebssystem einen lokalen Netzwerkdialog zeigen; die
App enthält dafür eine deutsche Zweckbeschreibung. Ein fehlendes/abgelehntes
OS-Recht wird nicht umgangen und ist kein bestandener Geräte-/UI-Nachweis.
Vor Änderungen der Verbindungsfelder die aktiven Einstellungen verwerfen. Ein
Quellenwechsel leert Katalog/Ergebnis und Schreibfreigabe. Keine Secrets protokollieren
oder in echten SQL-Literalen als Verbindungstest verwenden.

Pro Operation wird eine neue Verbindung aufgebaut. Daher werden Sessionvariablen,
TEMP-Tabellen oder Transaktionen nicht für die nächste Ausführung erhalten. Der
Standardlesemodus ist eine DB-erzwungene READ-ONLY-Transaktion, keine vollständige
Sandbox. Bewusste Schreibfreigabe gilt für die aktive Quelle; vollständige Befehle
werden in einer Transaktion committed. VACUUM/CREATE DATABASE und andere außerhalb
von Transaktionsblöcken nötige Befehle sind kein zugesicherter Umfang.

NULL, Leertext/-blob, Binärbytes/Base64, Int64, Numeric40,20, Boolean und Zeitwerte
werden getrennt erhalten.
Zeitwerte verwenden den proleptisch-gregorianischen Kalender, sechs exakte
Mikrosekundenstellen und bei BC den ausdrücklichen Suffix ` BC`; timestamptz wird
als UTC mit Z dargestellt. ±infinity und große Jahreszahlen bleiben sichtbar.
Der unabhängige Kalendervergleich ist auch einzeln mit
`python3 scripts/check-calendar-vectors.py` ausführbar.
Unbekannte PostgreSQL-Typen bleiben verlustfreie Binärbytes
mit OID; kein vollständiger Editor für alle Extensiontypen. Bytegrenzen gelten
für Rohzellen und encodierte Ergebnisdarstellung. Größenfehler liefern kein
Teilergebnis, Zeilenkürzung bleibt sichtbar. `rows_affected` wird für diesen
Streamingpfad nicht erfunden.

Ein Abbruch nutzt zusätzlich eine verifizierte, authentifizierte Verbindung zum
Signalisieren ausschließlich der eigenen markierten DB-Session. Der zusätzliche
Connect-/Queryversuch kann die sichtbare Deadline um bis zu circa vier Sekunden
verlängern; Netzwerk-/OS-Scheduling sind keine harte Echtzeitgarantie. Ist der
serverseitige Abbruch nicht bestätigt, wird genau das angezeigt. Kein Rollback-
versprechen, kein Abbrechen fremder Sessions, keine erweiterten DB-Rechte nötig.
Vollständiger Vertrag und konkrete Lizenz-/Upstreampins: [ADR-A002](docs/decisions/ADR-A002-direct-postgres.md).

Echte, ausschließlich eigene Wegwerfproben (Docker und OpenSSL müssen bereits
vorhanden sein; es werden keine globalen Tools installiert):

```sh
python3 scripts/test-postgres.py
```

Das Skript erzeugt drei zufällig benannte PostgreSQL18.6-Container mit dynamischen
Loopbackports und eigenen öffentlichen Testzertifikaten, führt native Swift-Tests
aus und entfernt ausschließlich diese Container/Volumes. Keine echten Credentials
oder Produktdaten. Es prüft TLS positiv/unknown CA/falscher Host/kein TLS, einen
gewöhnlichen Nicht-Superuser, Readonly-/Writeconsent-/Batchregeln, exakte Werte,
Zeilen-/Byte-/Zeitlimits, tatsächlich laufende Abfrage, Cancellation und nachfolgende
DB-Freigabe sowie UI-Modellwechsel. Ohne Fixtureumgebung sind diese Livetests
ausdrücklich als übersprungen markiert; `check-apple.sh` allein ersetzt sie nicht.
Öffentliche Apple-CI prüft den Build-/Unitstand ohne behauptete Docker-Livetests.
Lokaler tatsächlicher Prüfstand und unabhängige QA stehen im [A2-Handoff](docs/handoffs/A2.md).
