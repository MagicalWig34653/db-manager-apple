# A-TF4 – Build 4 mit iPhone und iPad

Stand: 24.10.2026. Branch `release/build4`, Basis `main` (803c44b, enthält A5).

## Änderung

- `CURRENT_PROJECT_VERSION` 3 → 4 (Debug und Release); Version `0.1.0`.
- `scripts/check-distribution.py`: erwartet Build `4`.
- `ITSAppUsesNonExemptEncryption = NO` unverändert ([A-TF3](A-TF3-compliance.md)).
- Keine Funktions- oder Icon-Änderung nötig: Projekt hatte bereits `TARGETED_DEVICE_FAMILY = "1,2"`,
  iPhone-Ausrichtungen, `UILaunchScreen_Generation`, AppIcon-Katalog und Deployment 26.0 ([A5](A5-mac-iphone.md)).
- Build 3 wurde laut Eigentümer hochgeladen; dessen Verarbeitung ist hier nicht geprüft.

## Tatsächlich ausgeführte Prüfungen

- Einzeln: `check-dependencies.py` (Pins und Checkouts), `swift test` (Kern- und 8 App-Tests bestanden),
  `check-calendar-vectors.py`, `check-docs.py`, `check-icon.sh` (Mac, iPad, iPhone bestanden, einmal standalone).
- `sh scripts/check-apple.sh` als Ganzes lief **nicht** durch: `actool` brach im iPad-Icon-Schritt ab und
  meldete einen Pfad eines fremden Projekts (`.../ClaudeWatch/Assets/AppIcon.icon`); vermutlich teilt sich der
  Icon-Dienst bei parallelen Builds anderer Agents den Zustand. Dreimal wiederholt, gleiches Ergebnis; die
  übrigen Build-Schritte des Skripts (macOS-/iOS-Simulator-Build) wurden deshalb nicht im Gesamtlauf geprüft.
  Ersatz: signierter Release-Archivbuild unten.
- `prepare-testflight.py --platform ios --provision --export`: signiertes Release-Archiv, `check-distribution.py --signed`
  (Identität, Icons, Privacy, Runpaths je Architektur) und lokaler App-Store-Export erfolgreich.
- IPA-Info.plist: `CFBundleVersion` 4, Version 0.1.0, `ITSAppUsesNonExemptEncryption = false`,
  `UIDeviceFamily` [1, 2], `MinimumOSVersion` 26.0, iPhone-Ausrichtungen vorhanden, `UILaunchScreen` vorhanden,
  `CFBundleIcons` mit AppIcon. LC_RPATH `@executable_path/Frameworks`; kein `Frameworks`-Ordner und keine
  `libswiftCompatibilitySpan.dylib` im Bundle (wie bei 26.0 erwartet). Team J2DU2P47XW.

## Nicht geprüft

- Upload, Apple-Verarbeitung, App-Store-Connect-Validierung (z. B. iPhone-Screenshots/Metadaten), CI.
- Kein Lauf auf echtem iPhone/iPad; keine interaktive Bedienung (siehe A5).
- Das Archiv/Export liegt lokal außerhalb von Git; der Upload erfolgt durch den Koordinator.
