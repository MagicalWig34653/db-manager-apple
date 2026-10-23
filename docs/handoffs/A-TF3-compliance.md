# A-TF3-compliance – Exportcompliance ausgenommen, Build 3

Stand: 23.10.2026. Paket des Delivery-Agents auf Branch `fix/export-compliance-exempt`.

## Anlass

Build 2 (`ITSAppUsesNonExemptEncryption = YES`, siehe [A-TF2](A-TF2-compliance.md)) wurde von
Apple dreimal mit „Invalid Export Compliance Code. The export compliance key value []
... doesn't match the key value of the app's export compliance documentation“ abgelehnt.
Build 2 wurde nie verarbeitet und erscheint in App Store Connect nicht als Build.

## Entscheidung

Der Eigentümer hat den Verschlüsselungsdialog in App Store Connect beantwortet
(Standardalgorithmen). Apple meldet ihm danach: „Basierend auf deinen Antworten musst du
keine Dokumente hochladen“; die App gilt demnach als ausgenommen. Frankreich schließt der
Eigentümer bewusst aus. Deshalb gilt nun `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`
(Debug und Release) und `CURRENT_PROJECT_VERSION = 3`; Version `0.1.0` bleibt.

Dies stützt sich auf die Erklärung des Eigentümers und Apples Antwort, nicht auf eine
eigene rechtliche Bewertung. Die rechtliche Ausfuhrerklärung liegt allein beim Eigentümer.

## Änderungen

- `DBManager.xcodeproj/project.pbxproj`: Schlüssel `NO`, Build 3.
- `scripts/check-distribution.py`: erwartet Build `3` und `ITSAppUsesNonExemptEncryption == false`.
- `Distribution/README.md`, `docs/STATUS.md`: nachgeführt.

## Tatsächlich ausgeführte Prüfungen

- `sh scripts/check-apple.sh` (Pins, `swift test`, macOS- und iOS-Simulator-Build mit
  Distributionscheck, `check-docs.py`): Exit 0.
- `python3 scripts/prepare-testflight.py --platform ipad --provision --export`:
  signiertes Release-Archiv und lokaler App-Store-Export erfolgreich, Distributionscheck
  mit Signatur bestanden.
- Info.plist der IPA: Version 0.1.0, `CFBundleVersion` 3, `ITSAppUsesNonExemptEncryption = false`;
  LC_RPATH `/usr/lib/swift` und `@executable_path/Frameworks`;
  `Frameworks/libswiftCompatibilitySpan.dylib` vorhanden.
- Nicht ausgeführt: Upload, Apple-Verarbeitung, CI-Lauf.

## Offen

Upload durch den Koordinator, Verarbeitungsstatus von Build 3 in App Store Connect.
