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

## Explizite Registrierung tatsächlich bestätigt

Lokaler App-Store-Export des ersten signierten iPadarchivs erfolgreich, ohne Upload.
Xcode hat über den vorhandenen Account ein explizites Distributionsprofil mit
App-ID J2DU2P47XW.de.linolaske.dbmanager erzeugt, CreationDate23.10.2026
05:29:43UTC, Plattform iOS, get-task-allow=false. Kein Wildcard. Damit kann der
Nutzer den ASC-NeueApp-Eintrag mit Bundle-ID de.linolaske.dbmanager fortsetzen.
Die tatsächliche Auswahl im Browser ist kein hier automatisierter UI-Nachweis.
Macarchive und erneuter finaler iPad-Archivstand mit vollständigen Metadaten laufen
noch; erster Export ist Registrierungsnachweis, keine Uploadfreigabe.

## Finaler lokaler Nachweis am eingefrorenen Appstand e45069c

- Erneutes signiertes iPad-Releasearchive mit endgültigen Metadaten/Icon bestanden;
  die anfängliche iPad-Orientierungswarnung durch explizite vier unterstützte
  Ausrichtungen behoben. Letztes Archive ohne diese Warnung. Übrig nur erwartete
  AppIntents-Metadata-Skipwarnung mangels AppIntentsabhängigkeit.
- Native macOS-Releasearchive tatsächlich signiert bestanden, Universalbinary
  x86_64+arm64. Tatsächliche Sandbox-, Networkclient- und ausgewählte-Dateien-
  Entitlements aus exportierter Mac-App rückgelesen und geprüft.
- Beide finalen **lokalen App-Store-Exports** bestanden: iPadIPA und MacPKG.
  Beide ausschließlich lokal entpackt, nicht installiert/hochgeladen/eingereicht.
  Strikte tatsächliche codesign-Prüfung, Team/Bundle-ID/Version/Build, PrivacyInfo,
  kompilierte Assets.car und ältere-OS-Iconfallbacks bestanden.
- Beide exportierten Apps enthalten explizite Apple-Distributionsprofile für
  J2DU2P47XW.de.linolaske.dbmanager ohne Debugberechtigung. Öffentliche nicht geheime
  [Registrierungsquittung](../../Distribution/registration-proof.json); keine
  Profil-/Zertifikat-/Privatschlüsselbytes im Repository.
- Jeweils13 Abhängigkeitspins und Originaltexte am tatsächlichen Archivprodukt
  mit check-dependencies.py --products bestätigt. Keine Änderung am Paketbaum.
- Tatsächliche Mac-ICNS-Fallbackgrafik extrahiert und visuell geprüft: aktuelles
  Tabellengitter im Vordergrund. Renderreihenfolge des Composers geprüft/korrigiert,
  finale Vorschauen in Assets/Previews entsprechen dem aktuellen Layerprojekt.
- Neue Prüfung: scripts/check-distribution.py --app <app> --signed
  --distribution-profile, auf beiden final entpackten Distributionapps bestanden.
  Dies ist keine serverseitige ASC-/TestFlightverarbeitung oder Gerätefreigabe.

Öffentliche exakte CI e45069c: Vault39906369410 und Docs39906369417 erfolgreich,
Apple39906369396 bei diesem Checkpoint noch aktiv. Frühere4badb7e-Prüfungen ersetzen
keinen Abschlussnachweis des letzten Commits. S2a-Main-Apple39903661074 inzwischen
tatsächlich erfolgreich. Kein Uploadwerkzeug oder Uploadziel ausgeführt.

Offene Freigaben: unabhängiger Review/Integration, finale öffentliche Apple-CI,
Eigentümerauskunft zu Verschlüsselung/Privacy und App-Store-/TestFlightmetadaten,
ASC-Apprecord im Browser sowie tatsächlicher späterer Upload nach ausdrücklichem
Auftrag. Kein physischer iPadlauf oder interaktiver Store-/Signingnachweis behauptet.
Lokale signierte Archive/Exports verbleiben nur im eigenen temporären Präfix
zwecks enger unabhängiger Prüfung; alle eigenen Build-/Exportjobs beendet.

Eigentümer meldet inzwischen den ASC-Apprecord „DB Manager“ als erstellt.
Keine zweite Anlage. Der vorhandene Xcodeaccount belegt erfolgreiche Developer-
Portal-/Distributionsauthentifizierung; eigenständiger lesender ASC-Apprecord-
APIzugriff ist dadurch nicht nachgewiesen. Keine ASC-APIkeys/Passwörter extrahiert,
kein Connector vorhanden. Appname/Plattformen/Versionsmetadaten im ASC daher bislang
Eigentümerauskunft, nicht unabhängig per API rückgelesen. Kein Uploadauftrag daraus
abgeleitet. Artefakthashes/Bytegrößen in registration-proof.json; konkrete lokale
Dateien für den freizugebenden späteren Upload sind dem Koordinator genannt.

## Öffentliche Reviewübergabe

Eingefrorener Gesamtkandidat b7020517d6431a852f61188f70c90e495534bdd2,
App-/Iconbytes unverändert seit e45069c; danach ausschließlich Prüfskriptintegration,
Registrierungsquittung und Dokumentation. Dokumentation140/0, Diffprüfung sauber,
Shell-/Python-Syntax geprüft. Exakte CIs:
[Docs39906842633](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842633)
bestanden;
[Apple39906842616](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842616)
und [Vault39906842798](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39906842798)
bei Übergabe aktiv, nicht vorweggenommen. Koordinator beobachtet den Abschluss.
Keine lokalen Build-/Export-/Composerprozesse mehr aktiv. Eigene signierte lokale
Artefakte bleiben für unabhängige Prüfung/konkrete Uploadentscheidung erhalten;
keine fremden Ressourcen oder Systemrechte verändert. Kein Mainmerge vorgenommen.
