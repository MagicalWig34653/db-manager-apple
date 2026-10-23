# Tatsächlicher Apple-Stand

Stand: 23.10.2026, A-TF1-Integrationscheckpoint. Neuer ausdrücklicher Nutzerabschluss:
erster Build auf TestFlight, Pages live sowie vollständige Doku-/Claude-Code-Übergabe.
Root koordiniert ausschließlich; Agents übernehmen die freigegebenen Schritte.
Offene Gesamtproduktfunktionen werden nicht als fertig behauptet.

## Integrierter Produktumfang

Eigenständiger SwiftUI-Arbeitsplatz ohne Go: ausgewählte lokale SQLite-Dateien und
direktes PostgreSQL mit verpflichtendem verifiziertem TLS, Katalog/Einzelstatement,
ausdrücklicher Schreibfreigabe, begrenzten getaggten Ergebnissen und Abbruch.
Credentials nur im Arbeitsspeicher, kein produktiver Geheimnisspeicher.

A1/A2 und isolierter S2a-Core sind nach unabhängigen Reviews integriert. Der Core
ist nicht in die App eingebunden; produktiver Anchor und Recovery-/Speicherablauf
bleiben gesonderte Gates. [A1](handoffs/A1.md), [A2](handoffs/A2.md),
[A2-Review](handoffs/A2-review.md), [S2a](handoffs/S2a.md),
[S2a-Review](handoffs/S2a-review.md), [ADR-A003](decisions/ADR-A003-vault-core.md).

## A-TF1 – technisch vorbereitete Distribution

Auf konkrete Leadfreigabe integriert: Feature bis6551a8a mit akzeptiertem
Sourcepin645c8c1b2dbd401410cdaf42afc0b221770f322e als7f5282e; unabhängiger
Erst-/CI-Nachreview bis7e6619e5d071ed7afdcd7d7ccaa11e3a81190099 als9a15581.
Volle Feature-/Reviewprovenienz erhalten, App-/Icon-/Xcode-/Sources-/Package-/
Distributionbytes gegenüber dem bereits geprüften b702051 unverändert.
[Autorenhandoff](handoffs/A-TF1.md), [unabhängiger Review](handoffs/A-TF1-review.md),
[Releasecheckpoint](handoffs/A-TF1-integration.md), [Vorbereitung](../Distribution/README.md).

- Bundle-ID **de.linolaske.dbmanager**, Version **0.1.0**, Build **1**.
  Explizite Apple-Distributionsprofile statt Wildcard tatsächlich belegt.
- Eigentümer hat den ASC-Eintrag „DB Manager“ angelegt und wurde zum Fortsetzen
  benachrichtigt. Keine separate ASC-API-/Browserprüfung des Eintrags behauptet.
- Signierte iPad-/Universal-Macarchive und lokale App-Store-Exporte IPA/PKG
  tatsächlich erfolgreich; strikte Signaturen, Profile, Entitlements, Versionen,
  Privacy/Icons und13 Originalnotice-/Abhängigkeitspins unabhängig geprüft.
- Eigenes echtes editierbares [Icon-Composer-Projekt](../Assets/AppIcon.icon/icon.json)
  mit zwei SVG-Layern, echte ictool-Vorschauen und kompilierte ältere-OS-Fallbacks.
  Keine GUI-/Accessibility-/ScreenRecordingrechte verändert.
- Beide finalen Exporte und zugehörigen Archive zusätzlich dauerhaft privat im
  lokalen Developerbereich gesichert; Datei-SHA256 und vollständige Archivbäume
  vor/nach Kopie gleich, keine bestehenden abweichenden Dateien überschrieben.
  Private lokale Receipt/README vorhanden, genaue Pfade nur an Eigentümer/Koordination.
  Keine Profile, Schlüssel, Archive oder Exportdateien im Git-/Releaseassetsbaum.

**Bisher kein Upload, keine Einreichung, keine TestFlight-/App-Store-Verfügbarkeit.**
Der Nutzer hat inzwischen den ersten TestFlight-Upload ausdrücklich autorisiert;
ein eigener Delivery-Agent übernimmt ihn, keine parallelen Uploads durch den
Releasekoordinator. Kein App-Store-Release und keine öffentlichen externen
Tester-Einladungen daraus. Betreiberangaben zu Verschlüsselung/Privacy und
TestFlightmetadaten müssen zum tatsächlichen Produkt passen. ITSAppUsesNonExemptEncryption wurde nicht
blind auf NO gesetzt; TLS/BoringSSL/SwiftCrypto und der nicht verknüpfte Vault-Core
sind dokumentiert. PrivacyInfo-SystemBootTime-Reason35F9.1 passt zu lokalen Timern;
DBkommunikation an Nutzerziele ist keine Zusage über deren serverseitige Logs.

## Tatsächliche CI- und Integrationsnachweise

Der erste Apple-Lauf39906842616 scheiterte am Icon-Assetruntime-Host. Diagnose
belegte fehlende CoreMedia-/MediaToolbox-Symbole; kein JSON-/Layerfehler behauptet.
Die kontrollierte Korrektur behält Xcode26.3/Swift6.2.4 sowie alle Prüfungen und
Deploymentminima, verwendet aber macos-26 und zusätzliche direkte actool-Preflights.
App-/Icon-/Paketbytes wurden dafür nicht verändert.

Alle drei exakten CIs am Sourcepin645c8c1 unabhängig completed/success:
[Apple39908768321](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39908768321),
[Vault39908768308](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39908768308),
[Docs39908768380](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39908768380).
Beide actool-Preflights,22 Swiftprüfungen,1.008 Datums-/4.032 Timestampvektoren,
13 Pins/Originaltexte und Mac-/iPad-Simulatorbuilds erfolgreich. Sechs ohne Fixtures
übersprungene Livetests sind keine neuen DB-Livenachweise. S2a-Main d0dea67 hatte
bereits alle drei kombinierten CIs erfolgreich abgeschlossen.

Begrenzter Releasecheck: Byte-/Ancestryprüfung,13 Rootpins/Originaltexte,
Shell-/Python-Syntax, Dokumentation/Diff, Exportdatei-SHA/Bytegrößen sowie volle
Dateibaummanifeste der privaten Archivkopien und deren strikte Signaturen/Identität
bestanden. Keine alten signierten Archive neu gebaut oder überschrieben, keine
unnötige native Vollmatrix wiederholt. Die neue Mainserie startet mit diesem
Veröffentlichungscheckpoint und wird noch nicht als erfolgreich behauptet.

## Offene Plattform-/Produktgates

G-S2b auf damaligem ad-hoc-Host ohne Team-ID: DP-Keychain-SecItemAdd=-34018,
keine Itemanlage/Dialogs/Fallbacks. Atomarer CAS, OS-Lock und Unsicherheitsfälle
auf geeignetem signierten/provisionierten Host bleiben separat zu beweisen.
Die neue Appsignierung schließt dieses Gate nicht automatisch. Kein produktiver
InMemory-/Dateifallback. G-S2b/C-Export1/A3 bleiben eigene Pakete nach Beauftragung.

macOS14/iPadOS17 sind Deploymentziele; echte Geräte, alte OS-Laufzeiten,
interaktive OS-UI und Runtime-Sandboxdurchsetzung sind nicht durch Signatur oder
Entitlements abgenommen. Kein nativer MySQL-/MariaDB-Adapter wegen belegtem
TLS-Downgrade, kein SSH/HTTP-Backendclient/Passkey/CloudKit/Teamumfang. READ ONLY
ist keine vollständige DBsandbox, Abbruch garantiert keinen Rollback.

Eigener Code AGPL-3.0-only, Abhängigkeiten behalten Originallizenzen. Keine eigenen
Build-/Signing-/Deployjobs oder Container offen. Originalartefakte unverändert
erhalten; private Kopien sind absichtliche Benutzerartefakte, keine zu bereinigenden
Scratchdateien. AppleSTATUS/Plan für diesen Release exklusiv beim Releasekoordinator,
weitere Zuweisung durch Root. [Arbeitsplan](ARBEITSPLAN.md), [Einrichtung](../EINRICHTUNG.md).

## A-TF2 – Exportcompliance, Build 2

Branch `fix/export-compliance`: `ITSAppUsesNonExemptEncryption = YES` (Standard-
verschlüsselung, Auswahl des Eigentümers in ASC), Build **2**, Version 0.1.0.
Lokal geprüft: `check-apple.sh` und signierter iPad-Release-Export (Info.plist mit
Schlüssel, Build 2). `libswiftCompatibilitySpan.dylib` ist im Export eingebettet.
Rechtliche Ausfuhrerklärung bleibt beim Eigentümer. Upload-/Verarbeitungsstatus
von Build 2 siehe [A-TF2](handoffs/A-TF2.md); nicht dort belegt gilt als offen.
