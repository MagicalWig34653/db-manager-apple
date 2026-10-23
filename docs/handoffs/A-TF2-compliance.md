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

Befund im exportierten Build 2: Die Binary referenziert
`@rpath/libswiftCompatibilitySpan.dylib` (RPATH `/usr/lib/swift`, kein weiterer
Eintrag). Die Bibliothek ist **eingebettet** unter `Frameworks/`, mit Teamsignatur
(arm64/arm64e, minos 12.2) signiert und liegt zusätzlich in `SwiftSupport/iphoneos`
des Archivs. Xcode packt sie beim Export selbst ein; eine fehlende Einbettung
wurde damit **nicht** reproduziert und es war keine Build-Setting-Änderung nötig.
Der genaue Wortlaut der ASC-Meldung liegt dem Agent nicht vor; ob sie bei Build 1
dieselbe Ursache hatte, wurde nicht geprüft. Bei erneutem Auftreten bei Build 2
bitte den vollständigen ASC-Text liefern.

## Offen

Upload von Build 2, Verarbeitungsstatus und CI-Ergebnis: siehe Abschnitt
„Ergebnis Upload/CI“ unten, falls ergänzt; sonst nicht belegt.
