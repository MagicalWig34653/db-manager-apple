# ADR-A004: Native Mac-Bedienung, iPhone-Unterstützung und Deployment-Ziel 26.0

Status: **Vorschlag zur unabhängigen Prüfung** (Paket A5, Branch `feat/mac-iphone-ui`).
Keine Geräte-, Signing-, Distributions- oder interaktive GUI-Freigabe.
Datum: 23.10.2026.

## Ausgangslage (geprüft)

- Das Xcode-Ziel `DBManager` baut mit `SDKROOT = auto`, `SUPPORTED_PLATFORMS = macosx iphoneos
  iphonesimulator` und `SUPPORTS_MACCATALYST = NO`. Der Mac-Build ist damit ein **natives macOS-Ziel**
  (kein Catalyst, kein „Designed for iPad“). `TARGETED_DEVICE_FAMILY = 2` schloss das iPhone aus.
  Zusätzlich war `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` nicht gesetzt; es ist jetzt ausdrücklich `NO`,
  damit der Mac nie als iPad-App läuft.
- Das iPad-Gefühl am Mac kam aus der Oberfläche: eine einzige Sidebar-Liste mit Buttons, keine Menüleiste,
  keine Kontextmenüs, Verbindungsformular dauerhaft in der Sidebar.

## Entscheidung 1: Oberfläche

- Eine `NavigationSplitView`; auf kompakter Breite (iPhone) einspaltiger Stack über `preferredCompactColumn`.
- Menüleiste über `Commands` und `FocusedValue`: Datei öffnen ⌘O, neue lokale Datei ⇧⌘N, PostgreSQL ⌘K,
  Ausführen ⌘↩, Abbrechen ⌘., Datenquelle schließen; ⌘N bleibt neues Fenster (mehrere unabhängige Fenster,
  jedes mit eigenem Modell). Tastatur-Toolbar „Ausführen“ auf iOS.
- PostgreSQL-Verbindung als Formular-Sheet (Tastaturtypen, keine Autokorrektur/Großschreibung auf iOS).
- Kontextmenüs für Objekte (Inhalt, Name kopieren) und Ergebniszeilen/-werte (kopieren), Hilfetexte (Hover).
- Fenster: Standardgröße 1100×720, Mindestgröße 820×540 auf macOS.
- Ergebnisse: breites Raster auf Mac/iPad; auf kompakter Breite scrollbare Kartenliste mit Detailansicht je
  Zeile (alle Spalten, Typ, Wert, Kopieren).
- `fileImporter` bleibt der Dateiauswahlweg auf allen Plattformen (am Mac das native Öffnen-Fenster).

## Entscheidung 2: iPhone-Mindestfunktionen

SQLite-Datei öffnen/anlegen, PostgreSQL verbinden (verifiziertes TLS), Objekte wählen, ein SQL-Statement
ausführen/abbrechen, Ergebnisse ansehen und Werte kopieren. Kein zusätzlicher Funktionsumfang; Schreibfreigabe
bleibt ausdrücklich. `TARGETED_DEVICE_FAMILY = "1,2"`, iPhone-Ausrichtungen Hoch plus beide Quer.

## Entscheidung 3: Deployment-Ziel 26.0

Gemessene Builds (Xcode 27.1, generischer Mac- und iOS-Simulator-Build, Debug):

| Minimum | `libswiftCompatibilitySpan.dylib` im Bundle |
|---|---|
| macOS 14 / iOS 17 (bisher) | eingebettet (Mac und iOS) |
| 26.0 | **nicht** eingebettet |
| 27.0 | **nicht** eingebettet |

Gewählt: **26.0** für `IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET` und die Package-Plattformen
(`.macOS(.v26)`, `.iOS(.v26)`). Begründung: 26.0 genügt bereits, um die Backdeploy-Bibliothek zu vermeiden
(das beseitigt das Runpath-/Einbettungsproblem aus A-TF2), und schließt weniger Nutzer aus als 27.0. Die vom
Nutzer erlaubte 27.0 brächte für dieses Problem keinen messbaren Vorteil. Die Messung ist ein Build-Befund; die
genaue Schwelle zwischen 17 und 26 wurde nicht bestimmt. Die CI nutzt Xcode 26.3, dessen SDK 26.0 kennt; ein
CI-Lauf mit dieser Änderung steht aus.
`check-distribution.py` verlangt weiterhin, dass eine eingebettete Backdeploy-Bibliothek einen Runpath hat;
sie fehlt nun einfach.

## Nachbesserungen aus dem unabhängigen Review (A5-review)

- ⌘O und ⌘K lösen keinen Quellwechsel mehr aus; die Quelle wechselt erst bei erfolgreicher Dateiauswahl bzw. beim
  tatsächlichen Verbinden. Abbrechen lässt Verbindung, SQL und CA unverändert.
- Das Passwort-Draft wird beim Schließen des Verbindungssheets verworfen.
- Objekte lassen sich auf macOS erneut anklicken (Auswahl wird zurückgesetzt).
- Kopieren legt Zellwerte in die Systemablage (iOS: ggf. Universal Clipboard). Das ist nutzerausgelöst; die UI
  weist in der Zeilenansicht darauf hin, die Datenschutzbeschreibung sollte es erwähnen.
- Ältere ADRs und Status nennen 14/17 als abgelöst; `check-icon.sh` prüft iPhone, iPad und Mac mit 26.0;
  `prepare-testflight.py --platform ios` (iPhone+iPad) ersetzt `ipad` (Alias bleibt).

## Offen

Interaktive Mac-GUI, echtes iPhone/iPad, Tastaturverhalten auf Gerät, VoiceOver/Dynamic Type, Archive/Export mit
`TARGETED_DEVICE_FAMILY = 1,2` (neue App-Store-Metadaten/iPhone-Screenshots, höhere Buildnummer bei Upload),
`scripts/prepare-testflight.py` (Plattformname `ipad` baut weiterhin generisches iOS; Umbenennung offen).
