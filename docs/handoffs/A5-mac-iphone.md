# Übergabe A5 – Native Mac-Bedienung und iPhone-Unterstützung

Branch `feat/mac-iphone-ui`, eigener Worktree `.worktrees/mac-iphone-ui`, Basis `main` (84c7504).
Status: Implementierung zur unabhängigen Prüfung; keine Integration, kein Upload, kein Archiv.
Entscheidungen und Begründung: [ADR-A004](../decisions/ADR-A004-mac-iphone-ui.md).
`Sources/DBManagerCore` wurde nicht verändert.

## Befund

- Das Projekt baut bereits ein **natives macOS-Ziel** (kein Catalyst, kein „Designed for iPad“).
  Das iPad-Gefühl kam aus der Oberfläche. `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` ist jetzt explizit gesetzt.
- `TARGETED_DEVICE_FAMILY = 2` schloss das iPhone aus; jetzt `"1,2"` mit iPhone-Ausrichtungen.
- Deployment-Messung (Xcode 27.1): Mit macOS 14 / iOS 17 wird `libswiftCompatibilitySpan.dylib` in Mac- und
  iOS-Bundle eingebettet; mit 26.0 und mit 27.0 nicht. Gewählt 26.0 (Xcode-Projekt und Package),
  siehe ADR. Package-Plattformen allein genügen nicht als Beleg; die Messung wurde mit Projekt-Targets
  26.0/27.0 gemacht (Variante 27.0 zusätzlich mit Package 27.0 und mit unverändertem Package).

## Umsetzung (Sources/DBManagerApp)

Aufgeteilt in `DBManagerApp.swift` (Scene, Menübefehle), `WorkbenchModel.swift`, `WorkbenchView.swift`,
`ResultViews.swift`; Verhalten des Modells unverändert.

- Menüleiste: Datei öffnen ⌘O, neue lokale Datei ⇧⌘N, PostgreSQL-Verbindung ⌘K, Ausführen ⌘↩, Abbrechen ⌘.,
  Datenquelle schließen, Lizenzen im Hilfemenü. ⌘N öffnet ein weiteres unabhängiges Fenster.
- Mac: Standardgröße 1100×720, Mindestgröße 820×540, Sidebar-Breitengrenzen, Toolbar „Ausführen/Abbrechen“,
  Kontextmenüs (Objekt, Ergebniszeile), Tooltips.
- PostgreSQL-Formular als Sheet (iOS: URL-/Zifferntastatur, keine Autokorrektur/Großschreibung).
- iPhone (kompakt): einspaltiger Stack (`preferredCompactColumn`), Wechsel in den Arbeitsplatz nach Auswahl,
  Ergebnisse als Kartenliste mit Zeilendetail (alle Spalten, Typ, Wert, Kopieren), Tastatur-Toolbar „Ausführen“,
  interaktives Schließen der Tastatur, aufklappbarer Hinweistext.
- Mindestumfang iPhone: SQLite öffnen/anlegen, PostgreSQL (verifiziertes TLS), SQL ausführen/abbrechen, Ergebnisse
  ansehen/kopieren. Kein zusätzlicher Funktionsumfang.
- Debug-only (`#if DEBUG`): Startargument `-DBMSyntheticDemo` (und `-DBMDemoDetail`) legt synthetische Daten für
  Screenshots an; nicht im Release.
- Projekt: Deployment 26.0, Geräte 1,2, iPhone-Ausrichtungen, neue Dateien im pbxproj, `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
  für Debug. `scripts/check-distribution.py` erwartet jetzt `UIDeviceFamily == [1, 2]`, iPhone-Ausrichtungen,
  iPhone-Icon-Fallback und Minimum 26.0.
- Tests: zwei neue Prüfungen (Zellanzeige NULL/leer/gekürzt; Render der kompakten Ergebnisliste ohne Screen-Recording).

## Tatsächlich geprüft

- `swift test`: 17 Kern- und 7 App-Tests bestanden (inkl. der neuen).
- `xcodebuild` generisch macOS und iOS Simulator (Debug, Signing aus): erfolgreich; keine
  `libswiftCompatibilitySpan.dylib` im Bundle; `check-distribution.py` bestanden für beide Bundles.
- Simulator iOS 27.0, iPhone 17: App installiert, startet, Sidebar-Stack mit synthetischer SQLite-Datei und Tabelle
  `kunden` per Screenshot gesehen (`simctl io screenshot`, keine Bildschirmaufnahme-Berechtigung).
- `scripts/check-apple.sh` als Ganzes lief **nicht** durch: `check-calendar-vectors.py` lief bei Systemlast (Load > 300 durch parallele Agents) in das 120-s-Timeout. Das Skript bestand einzeln erneut (1.008 Datums-/4.032 Timestampvektoren); Icon-, Dependency-Pin-Prüfung und Tests liefen im Gesamtlauf bzw. einzeln erfolgreich, die Build-/Distributionsprüfungen wurden einzeln wie oben ausgeführt. Ein sauberer Gesamtlauf auf ruhigem Host steht aus.
- `scripts/check-docs.py` bestanden, `check-dependencies.py --products` für beide Builds bestanden.

## Nicht geprüft / offen

- Kein echtes iPhone/iPad, kein interaktives Mac-GUI (Menüs, Tastaturkürzel, mehrere Fenster, Kontextmenüs,
  Sheet-Größen sind nur kompiliert, nicht bedient). Fokuspfad der `FocusedValue`-Befehle ungeprüft.
- iPad- und iPhone-Detailansicht (Arbeitsplatz mit Ergebnisliste) konnten wegen hängender Simulator-Dienste
  (parallele Agents teilten den Simulator, Geräte wurden zwischendurch gelöscht) nicht als Screenshot belegt werden.
- Kein Mac-Fenster-Screenshot; kein Test mit PostgreSQL auf dem iPhone; kein VoiceOver/Dynamic-Type-Test.
- CI (`.github/workflows/apple.yml`, Xcode 26.3) mit Deployment 26.0 nicht gelaufen; Branch wird gepusht, Lauf abwarten.
- Raster auf Mac/iPad weiterhin handgebautes Grid (kein `Table`, Spalten nicht verschiebbar/sortierbar).
- Archive/Export mit iPhone-Familie, App-Store-Metadaten/iPhone-Screenshots, Buildnummer (3 bleibt) und
  `prepare-testflight.py` (Plattformname `ipad`) nicht angefasst; vor Upload höhere Buildnummer nötig.
- Drag-and-drop von Dateien und Mac-Einstellungsfenster bewusst nicht umgesetzt.
