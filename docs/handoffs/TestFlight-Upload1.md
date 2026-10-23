# TestFlight-Erstupload – 0.1.0 (1)

Stand: 23.10.2026, tatsächlicher Uploadabschluss 06:36:36 UTC.
Eigener Dokumentationsbranch `docs/testflight-upload`; keine App-, Icon-, Signing-,
Versions- oder Mainänderung durch den Delivery-Agent.

## Autorisierung und unveränderte Identität

Der Eigentümer hat den App-Store-Connect-Eintrag „DB Manager“ angelegt und danach
als konkreten Abschluss den ersten Build auf TestFlight, die öffentliche Pagesseite
sowie vollständige Dokumentation/Claude-Code-Übergabe beauftragt. Damit ist der erste
TestFlight-Upload autorisiert. Kein App-Store-Produktionsrelease, kein Macupload und
keine öffentliche externe Testereinladung wurden ausgeführt.

- Bundle-ID: `de.linolaske.dbmanager`.
- Version: `0.1.0`; Build: `1`; Plattform: iPad/iOS.
- Geprüfter Vorbereitungs-/CI-Sourcepin: `645c8c1b2dbd401410cdaf42afc0b221770f322e`.
- Unabhängiger Artefakt-/CI-Nachreview: `59c7004` / `7e6619e`.
- Ausgangs-IPA SHA256: `cb9be4a57944c5d1a1395ffd590ce7974a6c478fb2decc6fee92cc53089fb34e`.

Vor dem Upload wurden die private dauerhafte IPA-Kopie gegen diesen Hash und
Bundle-ID/Version/Build des zugehörigen Archivs direkt geprüft. Originale IPA,
PKG und Archive sind unverändert erhalten. Xcode paketiert das bereits gebaute
Archiv für den Upload neu; daraus wird keine ungeprüfte Bytegleichheit des
neupaketierten Uploadcontainers zur ursprünglichen IPA behauptet.

## Tatsächlich ausgeführter Upload

Genau **ein** unterstützter Xcode-Aufruf `xcodebuild -exportArchive` mit dem
geprüften iPadarchiv, eigenem privaten Optionsfile und vorhandener autorisierter
Xcode-Accountauthentifizierung. Optionen:

```text
method=app-store-connect
destination=upload
manageAppVersionAndBuildNumber=false
signingStyle=automatic
teamID=J2DU2P47XW
uploadSymbols=true
```

Keine Original-ExportOptionsdatei verändert, keine neue Buildnummer, kein Neubau
und keine Accounttokens/Schlüssel aus dem Keychain extrahiert. Der Aufruf endete
mit Exitcode **0**. Der Apple-Uploader meldete abgeschlossene Dateiübertragung,
serverseitigen Beginn der Paketverarbeitung, erfolgreichen Upload und abschließend
`EXPORT SUCCEEDED`. Dies ist ein tatsächlicher Uploadnachweis, kein bloßer lokaler
App-Store-Export. [Apple: Builds hochladen](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

Der vollständige ungefilterte Upload-/Distributionslog und eine maschinenlesbare
lokale Quittung sind ausschließlich im privaten Developer-Artefaktbereich neben
den geprüften Exporten gesichert. Sie werden weder committed noch veröffentlicht.
Keine Profile, Passwörter, Tokens, privaten Accountdaten oder absoluten privaten
Benutzerpfade in diesem Handoff.

## Statusgrenze und nächster notwendiger Nachweis

Letzter authentifizierter Serverstatus: **hochgeladenes Paket wird verarbeitet**.
Ein terminaler Verarbeitungsstatus oder `Ready to Test` ist damit ausdrücklich
**noch nicht belegt**. Apple verarbeitet neue Builds nach der Übertragung separat;
die Buildanzeige/Testverfügbarkeit darf nicht aus lokalem Exitcode abgeleitet werden.
[Apple: Buildstatus](https://developer.apple.com/help/app-store-connect/reference/app-build-statuses/).

Der tatsächlich installierte `xcrun altool --build-status` wurde einmal ohne
separate Credentials und mit geschlossenem stdin geprüft: Exit1, eindeutige
Authentifizierungsanforderung für ASC-JWT oder Username/app-spezifisches Passwort
mit Provider-ID. Dieses Werkzeug übernimmt Xcodes Accountauth nicht. Keine Secrets
angefordert, kein Tokenzugriff, kein Uploadretry oder unautorisierte Statusschleife.

Der Koordinator fragt den Eigentümer nach dem tatsächlichen ASC-Status unter
DB Manager → TestFlight → iOS → 0.1.0 (1). Bei fehlender Exportcompliance muss die
Auskunft zur tatsächlichen TLS/BoringSSL/SwiftCrypto-Nutzung passen; der isolierte
Vault-Core ist weiterhin nicht in die App gelinkt. Kein blindes `NO`, keine
Erfindung einer Betreiberattestation. Der Schlüssel
`ITSAppUsesNonExemptEncryption` wurde durch diesen Upload nicht gesetzt.
[Apple: Exportangaben für Betabuilds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/).

## Prozesse und Fortsetzung

Uploadprozess und einmaliger Statusversuch sind terminal, keine Delivery-,
Signing-, Compiler- oder Pollingjobs des Agents offen. Private Benutzerartefakte
und Quittung absichtlich erhalten; keine fremden Ressourcen geändert.

Nächster Schritt: Eigentümerstatus/Compliance beantworten lassen, tatsächliche
TestFlight-Verfügbarkeit belegen und ausschließlich die Abschlussdokumentation
nachziehen. **Kein erneuter Upload** ohne belegte Notwendigkeit. Dieser Zwischenstand
ist keine App-Store-Einreichung, Gerätefreigabe oder vollständige Projektabnahme.
