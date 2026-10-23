# A-TF2-compliance – Exportcompliance und Build 2

Stand: 23.10.2026. Paket des Delivery-Agents auf Branch `fix/export-compliance`.

## Anlass und Entscheidung

App Store Connect verlangte zu Build 1 eine Exportauskunft. Der Eigentümer hat dort
„Standardmäßige Verschlüsselungsalgorithmen“ gewählt. Entsprechend setzt das Projekt
nun `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = YES` (Debug und Release), damit
jede weitere Buildnummer ohne erneute Rückfrage mit derselben Angabe ankommt.
Version `0.1.0` bleibt, `CURRENT_PROJECT_VERSION` steigt von 1 auf **2**
(Apple verlangt eine höhere Buildnummer je Upload).

Begründung der Angabe (technischer Befund, keine Rechtsauskunft):

- TLS für PostgreSQL über swift-nio-ssl/BoringSSL (verpflichtend, verifiziert).
- SwiftCrypto/BoringSSL ist als Abhängigkeit gelinkt.
- Der Tresor-Core (AES-256-GCM, Argon2id) ist **nicht** in die App eingebunden,
  wäre aber ebenfalls Standardverschlüsselung.

Die rechtliche Ausfuhrerklärung (z. B. Selbstklassifizierung, ggf. BIS/Jahresbericht)
bleibt allein beim Eigentümer; dieses Paket erstellt keine Attestation.

## Änderungen

- `DBManager.xcodeproj/project.pbxproj`: Schlüssel gesetzt, Build 2.
- `scripts/check-distribution.py`: erwartet jetzt Build `2` und
  `ITSAppUsesNonExemptEncryption == true` statt dessen Abwesenheit.

## Tatsächlich ausgeführte Prüfungen

- `sh scripts/check-apple.sh` (Icon, Pins, `swift test`, Datumsvektoren, macOS- und
  iOS-Simulator-Build mit Distributionscheck, `check-docs.py`): Exit 0.
- `python3 scripts/prepare-testflight.py --platform ipad --provision --export`
  in neuem Ausgabeverzeichnis: Release-Archiv und lokaler App-Store-Export
  erfolgreich; Distributionscheck mit Signatur bestanden. Info.plist der IPA:
  Version 0.1.0, Build 2, `ITSAppUsesNonExemptEncryption = true`.

## libswiftCompatibilitySpan.dylib

Befund (Ursache siehe [A-TF2](A-TF2.md)): Die Datei war eingebettet, die Binary
lud sie aber per `@rpath` bei ausschließlich `LC_RPATH=/usr/lib/swift`, also ohne
app-lokalen Frameworkspfad. Behoben durch die Runpath-Einstellungen aus dem
Diagnosebranch (iOS `@executable_path/Frameworks`, macOS `@executable_path/../Frameworks`).
Im neu gebauten, signierten iPad-Export (Build 2) tatsächlich geprüft: LC_RPATH
`/usr/lib/swift` und `@executable_path/Frameworks`, Bibliothek in `Frameworks/`,
Preflight „Per-architecture embedded dependency runpaths“ bestanden. Der genaue
ASC-Meldungstext lag dem Delivery-Agent nicht vor; ob die Meldung nach Upload
verschwindet, ist erst nach der Serververarbeitung belegbar.

## Upload-Versuch Build 2: abgelehnt

Ein Upload (`xcodebuild -exportArchive`, destination=upload, privates Optionsfile,
Archiv des Commits d38b930, Build 2) wurde von Apple vor der Verarbeitung abgelehnt:
„Invalid Export Compliance Code. The export compliance key value [] in the app's
Info.plist doesn't match the key value of the app's export compliance documentation.“
Exit 70, kein Build in der Verarbeitung. Apple verlangt demnach zusätzlich
`ITSEncryptionExportComplianceCode` mit dem Code der in App Store Connect hinterlegten
Exportdokumentation. Dieser Code ist ausschließlich dem Eigentümer zugänglich
(App Store Connect, Apps, Exportcompliance-Dokumentation); er wurde nicht geraten.
Alternative: Dokumentation/Code entfernen oder die Auswahl in ASC so ändern, dass
kein Code erwartet wird. Kein weiterer Uploadversuch bis zur Eigentümerentscheidung.

## Offen

Code des Eigentümers, danach Upload, Verarbeitungsstatus. CI-Ergebnis siehe GitHub.
