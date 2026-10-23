# TestFlight lokal vorbereiten

App: de.linolaske.dbmanager · Team J2DU2P47XW · Version0.1.0 · Build1.
Ein gemeinsamer App-Store-Eintrag kann iOS/iPadOS und macOS umfassen; separat
archivieren und später nach ausdrücklicher Freigabe getrennt hochladen.
Bundle-ID muss als explizite ID im Developeraccount registriert sein. Ein
Wildcard-Developmentprofil reicht als Sichtbarkeitsbeleg nicht aus.

```sh
python3 scripts/prepare-testflight.py --platform ipad --output-dir /tmp/db-manager-ipad-preflight
python3 scripts/prepare-testflight.py --platform mac --output-dir /tmp/db-manager-mac-preflight
```

Standard: unsigniertes lokales Archive. Mit `--provision` darf Xcode den bereits
vorhandenen Developeraccount für App-IDs/Profile/Signing benutzen. `--export`
benötigt `--provision` und erzeugt nur einen lokalen App-Store-Export. Die fest
geprüfte ExportOptions-Datei hat destination=export, niemals upload. Neue leere
Ausgabeverzeichnisse wählen; keine bestehenden Archive überschreiben.

Keine Zertifikate, Profile, p8/p12-Schlüssel oder lokale Logs in Git einchecken.
Kein Toolinstall, keine Truststore-/Keychainrechte ändern. Fehlende/abgelaufene
Accountberechtigungen konkret beheben; kein unsicherer Signingfallback.
Vor Upload: eindeutige höhere Buildnummer, Distributionvalidierung, tatsächliche
Privacy-/Exportauskunft des Betreibers, TestFlightinformationen und unabhängiger
Review. [Tatsächlicher Nachweisstand](../docs/handoffs/A-TF1.md).
