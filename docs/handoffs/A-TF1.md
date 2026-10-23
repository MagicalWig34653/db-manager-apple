# A-TF1 – TestFlight-Vorbereitung

23.10.2026. Eigener Branch release/testflight-preparation ab Apple-main e50d745.
Nutzerauftrag: Bundle-ID unter de.linolaske und TestFlightvorbereitung; zusätzlich
editierbarer Icon-Composer-Entwurf. Kein Upload, keine App-Store-Einreichung.
Unabhängiger Review vor Integration, bestehende App-/Corefunktionen unverändert.

## Früher tatsächlicher Prüfstand

Ein Xcode-Appziel DBManager, macOS14/iPadOS17, nur iPad als iOS-Gerätefamilie;
keine eigenen Xcode-Testbundles (SwiftPM-Core-/App-Testtargets bleiben unverändert).
Bisher org.dbmanager.workbench, kein Team und keine explizite Releaseversion.
Jetzt einheitlich **de.linolaske.dbmanager**, Team J2DU2P47XW aus dem einzigen
vorhandenen bezahlten Individual-Account, Version0.1.0/Build1. Gemeinsame ID für
beide Plattformen als eine App; native Mac-App, kein Catalyst. Vorhandene lokale
Signingidentität gültig, keine privaten Schlüssel/Accountdaten veröffentlicht.

Echter generischer iPad-Gerätebuild und erstes signiertes iPad-Releasearchive
bestanden. Dabei vorhandenes **Wildcard-Developmentprofil** benutzt: dies beweist
KEINE explizite Portalregistrierung oder Sichtbarkeit im ASC-Auswahlfeld.
Lokaler App-Store-Export mit destination=export zur Profil-/ID-Prüfung gestartet,
Ergebnis beim frühen Checkpoint noch offen. Kein vorweggenommenes ASC-Weiter-Signal.

Xcode27.1 unterstützt -dry-run nicht mehr; früher rein lesender Vorversuch wurde
mit Exit64 abgelehnt und ist kein Buildnachweis. Danach regulär gebaut.

## Icon Composer

Eigene AGPL-Vektoren, zwei Ebenen Datenbank/Tabellengitter. Editierbare Quelle
[AppIcon.icon](../../Assets/AppIcon.icon/icon.json), [Entwurfsdokumentation](../../Assets/README.md).
Tatsächlicher installierter Icon Composer27.1/129, dessen mitgelieferter ictool
rendert Default iOS/Mac1024, Dark iOS1024 sowie Mac16 erfolgreich.
[1024px-Vorschau](../../Assets/Previews/AppIcon-iOS-Default-1024.png).
Keine GUIautomations-/Accessibility-/ScreenRecordingrechte geändert; keine
flache PNG als editierbares Projekt ausgegeben. Xcode-Resourcesphase und
ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon verknüpfen das echte Layerdokument.
Actool/Appbundle- und finales Archivprüfergebnis separat nachtragen.

## Datenschutz, Verschlüsselung und Grenzen

Eigene App hat keine Telemetrie, Trackingdienste, Analytics oder Betreiber-Upload.
SQL und Credentials gehen ausdrücklich an das vom Nutzer gewählte DBziel; diese
Funktion ist keine Zusage, dass auf einem fremden DBserver keine Logs entstehen.
PrivacyInfo deklariert keine Appbetreiber-Datensammlung/Tracking sowie den
belegten SystemBootTime-Reason35F9.1 für lokale Abfragedauer/Timeouts. Originale
Privacy-Manifeste der eingebundenen Abhängigkeiten bleiben unverändert vorhanden.
Store-Datenschutzangaben und Privacy-Policy müssen den tatsächlichen lokalen/
Direktverbindungsumfang beschreiben und vor Veröffentlichung bestätigt werden.

ITSAppUsesNonExemptEncryption im finalen Projekt **nicht gesetzt**. Die App linkt
TLS über PostgresNIO/NIOssl/BoringSSL und SwiftCrypto transitiv, nicht ausschließlich
URLSession-/OS-TLS. Eigenständiger Vault-Core ist nicht in die App eingebunden.
Kein blindes NO und kein vermeintlich von Apple geprüfter Exportstatus. Betreiber
muss die konkrete Exportauskunft einschließlich Bibliotheken vor Upload bestätigen;
ASC-Fragebogen bleibt absichtlich offen. Ein früheres Archiv vor endgültigem
Metadatencheckpoint ist kein veröffentlichbares finales Artefakt.

[Lokale Vorbereitung](../../Distribution/README.md), keine automatischen Uploadpfade.
Signierte Mac-Archives, finaler iPadstand, Distributionexport/Validierung, echte
Geräte/OSdialoge und vollständige ASC-Metadaten sind beim frühen Checkpoint offen.

## Primärquellen

- [App-ID registrieren](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- [ASC-Eintrag anlegen](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Distribution vorbereiten](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Required-Reason-APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Verschlüsselungsdeklaration](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)

Lokale Logs/Archive enthalten Signing-/Profilinformationen und bleiben außerhalb
Git. Keine fremden Profile/Items/Truststores/Systemrechte verändert. Provisioning
nur über vorhandenen autorisierten Account; keine Schlüssel exportiert.
