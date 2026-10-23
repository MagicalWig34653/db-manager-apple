# Unabhängiger Review A-TF1

Stand: 23.10.2026. Eigener Reviewworktree `.worktrees/atf1-review`, Branch
`review/atf1`. Reviewer hat weder A-TF1 noch Icon/Signingkonfiguration implementiert.
Geprüft: Produkt-/Prüfstand `b7020517d6431a852f61188f70c90e495534bdd2`,
reiner Autorenhandoff `a350f75d34508a020c24feb2e20f459c925f80d4`, Gesamtdiff
ab `e50d745`. Keine Produktänderungen durch den Reviewer.

## Urteil und Gate

**Kein bestätigter Befund. A-TF1 ist fachlich als begrenzte TestFlightvorbereitung
zur Leadintegration geeignet.** Die noch laufende exakte Apple-CI39906842616 muss
vor abschließender Integration erfolgreich sein; kein vorweggenommener CI-Erfolg.
Kein Upload, keine Einreichung und keine Store-/TestFlightverarbeitungsfreigabe.
Betreiberangaben zu Verschlüsselung, Privacy und TestFlightmetadaten bleiben vor
Upload ausdrücklich offen. Der von Nutzerseite angelegte ASC-Eintrag „DB Manager“
wurde hier nicht über eine gesonderte ASC-API oder Browserautomation geprüft.

## Tatsächlich unabhängig geprüft

- Gitstatus am übernommenen Reviewworktree sauber; keine frühere fertige
  Reviewdatei und keine laufenden A-TF1-/Xcode-/Vaultprüfprozesse vorhanden.
- Gesamtdiff begrenzt auf Bundle-/Signing-/Versions-/Icon-/Privacy-/Archivekonfiguration,
  Prüfwerkzeuge, Dokumentation und Quittung. `Sources`, Root-Package und beide
  bestehenden Lockfiles gegenüber dem vorherigen main unverändert.
- Originale lokale IPA-/PKG-Exporte vor Entpacken selbst mit SHA256 und Bytezahl
  aus `Distribution/registration-proof.json` verglichen: beide exakt identisch.
  Originale Archive und Exporte nicht verändert oder gelöscht.
- IPA und PKG in einem ausschließlich eigenen temporären Verzeichnis entpackt;
  ZIP-Pfade zuvor auf absolute Pfade und Parenttraversal geprüft. Beide tatsächlichen
  Apps mit `codesign --verify --deep --strict` sowie dem vorhandenen
  `scripts/check-distribution.py --signed --distribution-profile` geprüft.
- Provisioningprofile selbst aus den exportierten Apps mit `security cms -D`
  gelesen: explizite `J2DU2P47XW.de.linolaske.dbmanager`, kein Wildcard,
  keine Debugberechtigung, keine Developmentgeräteliste und kein Enterpriseflag.
  Appsignaturentitlements passen zur Profilidentität. Keine Profil-/Keybytes
  in diese öffentliche Dokumentation übernommen.
- Auf beiden tatsächlichen Apps Bundle-ID `de.linolaske.dbmanager`,
  Version0.1.0/Build1 geprüft. iPad-Gerätefamilie ausschließlich2, vier Ausrichtungen,
  kompilierter Iconkatalog und älterer iPadOS-Iconfallback vorhanden.
  Mac-App universal `arm64` und `x86_64`; `app-sandbox`, Networkclient und
  UserSelectedFile-ReadWrite sind in der exportierten Signatur tatsächlich gesetzt.
  Das ist ein Entitlementnachweis, kein ausgeführter Sandbox-/Gerätetest.
- Mit `xcrun vtool -show-build` tatsächliche Deploymentminima der Binärdateien
  geprüft: iPadOS17.0 und macOS14.0. Keine Laufzeitprüfung dieser alten OS-Versionen.
- `pkgutil --check-signature` bestätigt echte Apple-WWDR-/Rootkette mit passendem
  Mac-App-Store-Installerzertifikat. Die Toolklassifikation „Development“ der
  WWDR-Kette wurde nicht mit einer Debug-App oder Developer-ID-Distribution verwechselt.
- Je13 gepinnte Abhängigkeiten und Originalnotices mit
  `scripts/check-dependencies.py --products <entpacktes-Produktverzeichnis>`
  an beiden exportierten Produkten unabhängig bestätigt.
- Echtes Icon-Composer-Dokument mit zwei editierbaren eigenen SVG-Layern und
  eigener Composerfüllung gelesen, AGPL-Herkunft in Rootlizenz/AssetsREADME geprüft.
  Installiertes `ictool` erneut auf derselben Quelle ausgeführt: iOS1024-Default
  byteidentisch zur committeten Vorschau. Default-/Dark1024 sowie Mac16 visuell
  geprüft; Datenbank-/Tabellenmotiv lesbar. Keine flache PNG als Layerquelle ausgegeben.
- Tatsächliche `PrivacyInfo.xcprivacy` in beiden Apps, SystemBootTime-Reason35F9.1
  und keine Tracking-/Datensammlungsdeklaration geprüft. Eigene Quellen verwenden
  `ProcessInfo.systemUptime` für lokale Querydauer und Timeoutberechnung;
  keine neue Telemetrie-/Betreiberübertragung eingeführt. Grund passt zur
  [Apple-Primärbeschreibung](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
  Dies ersetzt keine vollständige betreiberseitige Store-Datenschutzauskunft.
- `ITSAppUsesNonExemptEncryption` in den tatsächlichen Produkten nicht blind auf
  NO gesetzt. TLS/BoringSSL/SwiftCrypto und fehlende Appverdrahtung des isolierten
  Vault-Core sind dokumentiert; Exportauskunft bleibt eine ausdrückliche Aufgabe.
- Exportkonfiguration fest `method=app-store-connect`, `destination=export`;
  Vorbereitungsskript enthält keinen Uploadpfad. Eigene Negativprobe ohne
  `--provision` weist `--export` vor Xcode-/Archiv-/Ausgabeverzeichniserstellung ab.
- Dokumentation140/0 und eigener Diffcheck bestanden. Öffentliche Pfad-/PEM-
  Privatkeysuche im A-TF1-Dateiumfang ohne Treffer. Keine Nutzer-/Accounttokens,
  privaten Profile oder Zertifikatprivatschlüssel veröffentlicht.

Eine vollständige native Buildmatrix wurde nicht redundant wiederholt: die
Produkte wurden tatsächlich unabhängig geprüft, Source-/Abhängigkeiten unverändert,
und exakte öffentliche Builds werden separat kontrolliert. Kein physischer iPadlauf,
interaktiver Icon-/OSdialog, installierter Home-Screen oder serverseitiger
TestFlight-/App-Store-Review hier nachgewiesen.

## Exakte öffentliche CIs und Ressourcen

Am geprüften `b7020517d6431a852f61188f70c90e495534bdd2`:

- [Docs39906842633](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842633): success.
- [Vault39906842798](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842798): success.
- [Apple39906842616](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842616): beim Abschlusscheckpoint tatsächlich in_progress, Job „Native Builds und Tests“ läuft. Kein Neustart ausgelöst.

Eigene Entpack-/Renderer-/Hilfsscratchdateien nach Prüfung entfernt. Keine eigenen
lokalen Jobs mehr. Keine OS-/Keychain-/Account-/Profiländerungen, keine fremden
Container und kein Host-Swarm berührt. Originale signierte Archive/IPA/PKG für den
Eigentümer unverändert erhalten. Nächster Schritt: Lead kontrolliert verbleibende
exakte Apple-CI und integriert bei Erfolg; Upload bleibt gesondert autorisiert.
