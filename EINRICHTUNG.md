# Einrichtung

Voraussetzungen: macOS mit Xcode und Swift 6, installiertem iOS-Simulator-SDK
sowie Python 3 für die Dokumentationsprüfung. Lokal geprüft: Xcode 27.1,
Swift 6.4, macOS-/iOS-SDK 27.0 auf Apple Silicon. Keine globale Toolinstallation,
keine externen Swift-Pakete und kein Go-Server erforderlich.

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
verwenden. Keine `Package.resolved` nötig, da keine Paketabhängigkeiten vorliegen.

## Anwendung

`DBManager.xcodeproj` öffnen, Schema `DBManager` und eigenen Mac oder iPad-Simulator
wählen. Für echtes Gerät oder Verteilung eigenes Signing konfigurieren; dieser
Auftrag veröffentlicht keine signierte App. Xcode enthält für macOS die deklarierte
App-Sandbox und Dateiauswahlberechtigung. Unsigned Builds beweisen deren Laufzeit-
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
