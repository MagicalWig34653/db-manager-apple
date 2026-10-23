# TestFlight lokal vorbereiten

App: de.linolaske.dbmanager · Team J2DU2P47XW · Version 0.1.0 · Build 3 (Build 1 bereits hochgeladen; Build 2 wurde von Apple vor der Verarbeitung abgelehnt und nie verarbeitet).
Ein gemeinsamer App-Store-Eintrag kann iOS/iPadOS und macOS umfassen; separat
archivieren und später nach ausdrücklicher Freigabe getrennt hochladen.
Bundle-ID muss als explizite ID im Developeraccount registriert sein. Ein
Wildcard-Developmentprofil reicht als Sichtbarkeitsbeleg nicht aus.

```sh
python3 scripts/prepare-testflight.py --platform ios --output-dir /tmp/db-manager-ios-preflight
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

Exportcompliance: `ITSAppUsesNonExemptEncryption = NO`. Grundlage ist die Erklärung des
Eigentümers in App Store Connect (Standardalgorithmen); Apple zeigte danach an, dass
keine Dokumente hochzuladen sind (App gilt als ausgenommen). Frankreich schließt der
Eigentümer bewusst aus. Rechtliche Ausfuhrerklärung beim Eigentümer. Jeder weitere
Upload braucht eine höhere Buildnummer.
[Details](../docs/handoffs/A-TF3-compliance.md), Vorgeschichte [A-TF2](../docs/handoffs/A-TF2-compliance.md).
