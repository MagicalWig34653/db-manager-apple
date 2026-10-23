# Unabhängiges Review A5 – Mac-Menüs, iPhone-Unterstützung, Deployment 26.0

Geprüft: `feat/mac-iphone-ui` (71efc29, Basis 84c7504), Review-Branch `review/a5-ui`. Reviewer ist nicht der Autor.
Host stark ausgelastet (Load > 400); Builds nacheinander. Xcode 27.1.

## Urteil

**Freigabe unter Auflagen für die Integration** (keine Blocker). Auflagen: Befunde M1 und M2 vor Upload/Release
beheben oder bewusst akzeptieren; CI-Lauf mit Xcode 26.3 abwarten (nicht belegt). Keine Freigabe für Upload,
Archiv oder GUI-Verhalten: nichts davon wurde geprüft.

## Eigene Läufe

| Prüfung | Ergebnis |
|---|---|
| `swift test` | 17 Kern- und 7 App-Tests bestanden (1 PostgreSQL-Live-Test übersprungen, keine Fixtures); Testbinaries `minos 26.0` |
| xcodebuild macOS generisch, Debug | erfolgreich; `check-distribution.py` und `check-dependencies.py --products` bestanden |
| xcodebuild macOS generisch, Release (x86_64+arm64) | erfolgreich; `check-distribution.py` bestanden |
| xcodebuild iOS Simulator generisch, Debug | erfolgreich (deckt iPhone und iPad ab); `check-distribution.py`, `check-dependencies.py --products` bestanden |
| `check-docs.py`, `check-dependencies.py` | bestanden (152 Dateien; 13 Pins) |
| Simulatorlauf iPhone/iPad | nicht ausgeführt (kein Simulator angelegt, Host überlastet); Layout nur per Code gelesen |
| `check-apple.sh` gesamt | nicht ausgeführt (Teilschritte einzeln wie oben) |

## Prüfpunkte

1. **Deployment 26.0.** Eigene Messung macOS: Build mit `MACOSX_DEPLOYMENT_TARGET=14.0` bettet
   `Contents/Frameworks/libswiftCompatibilitySpan.dylib` ein; bei 26.0 fehlt sie, im macOS- und im iOS-Bundle
   (`find` ohne Treffer), `otool -L` ohne Compat-Abhängigkeit. iOS-Gegenmessung (17) und die Variante 27.0 nicht
   selbst wiederholt; die ADR-Tabelle dazu bleibt Angabe des Autors. Runpaths vorhanden
   (`@executable_path/../Frameworks` bzw. `@executable_path/Frameworks`). Projekt und Package.swift stehen konsistent
   auf 26.0 (`minos 26.0`, `LSMinimumSystemVersion`/`MinimumOSVersion` 26.0). 26 statt 27 ist vertretbar: CI
   (`apple.yml`) nutzt `macos-26` und Xcode 26.3; die ADR-Begründung (kein messbarer Vorteil von 27) ist plausibel.
   Ob Xcode 26.3 mit `.v26` und der 27er-SDK-unabhängigen Quelle baut, ist nicht belegt (siehe M1). Der Autor
   benennt die ungeklärte Schwelle zwischen 17 und 26 ehrlich.
2. **Gerätefamilie/Sandbox.** `TARGETED_DEVICE_FAMILY = "1,2"`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`,
   `SUPPORTS_MACCATALYST = NO` in Debug und Release. iPhone-Ausrichtungen Hoch + beide Quer (kein Kopfüber, üblich).
   Entitlements, `Distribution/`, `PrivacyInfo.xcprivacy` und `DBManagerCore` im Diff unverändert; `codesign`-Ausgabe
   des unsignierten Builds zeigt keine Entitlements (erwartbar), Sandbox-Prüfung am signierten Build nicht möglich.
3. **Modellaufteilung.** `WorkbenchModel` (Zeilen 14-152 alt, 7-145 neu) ist per `diff` byte-identisch; nur
   `displayText/fullText/displayNote` und die DEBUG-Demo wurden ergänzt. Passwortlebensdauer (Löschen in
   `connectPostgres`, `changeSource`, `open`, `close`), Write-Consent (`allowWrites` bei jedem Quellwechsel
   zurückgesetzt, Toggle nur mit aktiver Quelle), Abbruch (`operation?.cancel()`) und `@MainActor` unverändert.
   Swift-6-Modus ohne Fehler/Concurrency-Warnungen im Build. Die Schaltfläche Passwort ist weiterhin
   `SecureField`.
4. **Menüs/Fenster.** Jedes `WorkbenchView` hält ein eigenes `@State`-Modell mit eigenen `SQLiteDatabase`/
   `PostgresDatabase`-Akteuren: zwei Fenster teilen weder Modell noch Verbindung (Code belegt, nicht bedient).
   Befehle laufen über `focusedSceneValue`, wirken auf das Fokusfenster; ohne Fokus sind sie deaktiviert.
   Kürzel ⌘O, ⇧⌘N, ⌘K, ⌘↩, ⌘. kollidieren nicht mit ⌘N. Nicht interaktiv bestätigt.
5. **iPhone/Release.** Kompakt: einspaltiger Stack, Kartenliste + Detailsheet, Tastatur-Toolbar. Nur Code gelesen.
   `-DBMSyntheticDemo`/`-DBMDemoDetail` und `loadSyntheticDemo` stehen hinter `#if DEBUG`;
   `DEBUG` wird nur in der Debug-Konfiguration gesetzt. Beleg: Release-Binary enthält 0 Treffer
   (`strings`), das Debug-iOS-Dylib 2 Treffer.
6. **check-distribution.py.** Nicht aufgeweicht, nur verschärft (Minimum 26.0, iPhone-Familie, iPhone-Orientierung,
   iPhone-Icon-Fallback). Die Runpath-Prüfung bleibt; fehlende Compat-Bibliothek ist weiterhin ein Fehler, wenn sie
   referenziert, aber nicht eingebettet ist. PrivacyInfo-Assertions unverändert.
7. **Doku.** Handoff und ADR sind überwiegend ehrlich (offene Punkte benannt). Abweichungen siehe L3, L4.

## Befunde

**M1 (mittel) CI-Verträglichkeit unbelegt.** Alle Messungen mit Xcode 27.1; `apple.yml` baut mit Xcode 26.3,
`vault.yml` (`macos-15`) mit Xcode 26.3 und Paket DBManagerVault (14/17, bleibt). Beleg: Workflows und
Package.swift. Fix: CI-Lauf auf dem Branch abwarten und im Handoff vermerken; Merge erst nach grünem Lauf.

**M2 (mittel) Menübefehle verwerfen aktive Verbindung ohne Rückfrage.** `openFile` (`changeSource(.sqlite)`) und
`connectPostgres` (`changeSource(.postgres)`) schließen die aktive Datenquelle, löschen Ergebnis/Schreibfreigabe
und CA, bevor Dateidialog oder Sheet erscheinen; Abbrechen des Dialogs lässt das Fenster ohne Quelle zurück.
Beleg: `WorkbenchView.actions`, `WorkbenchModel.changeSource`. Fix: Wechsel erst nach erfolgreicher Auswahl bzw.
beim Verbinden; oder Bestätigung. Kein Sicherheitsproblem (verschlechtert nur die Bedienung, Schreibfreigabe wird
sicher zurückgesetzt).

**L1 (niedrig) Passwort bleibt im Modell, wenn das Verbindungssheet ohne Verbinden geschlossen wird.** Gleiches
Verhalten wie zuvor in der Sidebar, aber das Sheet macht Schließen häufiger. Fix: `password = ""` im
Schließen-Handler.

**L2 (niedrig) Fehler doppelt sichtbar** (Sidebar und Detail); auf macOS erneutes Anklicken desselben Objekts
führt nicht erneut aus (Selektion bleibt; nur Kontextmenü). Fix: Selektion nach Ausführung zurücksetzen.

**L3 (niedrig) Doku-Rest.** `EINRICHTUNG.md` (Zeile 18: "Deploymentziel 14/17"), `docs/STATUS.md` (macOS14/iPadOS17),
ADR-A001/A002 und `scripts/check-icon.sh` (14.0/17.0, nur iPad-Gerät) nennen weiter die alten Ziele bzw. prüfen
nicht die iPhone-Variante des Icons. Fix: Status aktualisieren, ADR-A004 als Ablösung verlinken, check-icon um
iPhone erweitern (Lead pflegt Status).

**L4 (niedrig) Handoff-Aussage.** "7 App-Tests" stimmt; die Aussage, das iPhone-Layout sei per Screenshot gesehen,
bleibt auf eine Sidebar-Ansicht beschränkt (vom Autor so benannt). Von mir nicht nachgeprüft.

**L5 (niedrig) Zwischenablage.** `Clipboard.copy` schreibt Zellwerte in die Systemablage (iOS: ggf. Universal
Clipboard). Nutzerausgelöst; Hinweis für die Datenschutzbeschreibung, keine Änderung nötig.

**I1 (Hinweis)** `prepare-testflight.py --platform ipad` baut weiter generisches iOS; Buildnummer 3 muss vor Upload
steigen (vom Autor benannt). Release-Archiv mit Familie 1,2 nicht geprüft.

## Nicht geprüft

Interaktive Mac-GUI, Menüfokus, Mehrfenster zur Laufzeit, iPhone/iPad-Simulator- oder Gerätelauf, VoiceOver,
Dynamic Type, signierte Builds/Sandbox, iOS-Gegenmessung 17 und Variante 27.0, `check-apple.sh` als Ganzes,
CI mit Xcode 26.3.
