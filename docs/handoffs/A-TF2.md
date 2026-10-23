# A-TF2 – Swift-Backdeployment und ITMS-90863

23.10.2026. Eigener Branch diagnosis/itms-90863 ab geprüftem Apple-main359666f.
Nutzer meldete Applewarnung für Version0.1.0/Build1 nach erfolgreichem Erstupload.
Kein automatischer zweiter Upload, keine Plattformabwahl oder Storeeinreichung.
Root hat den engen Runpath-/Preflightfix und korrigierten Build2 ausdrücklich
freigegeben; Produktlogik, Datenbankadapter, Vault und Icons unverändert.

## Tatsächlicher Befund vor Korrektur

- Privater Uploadnachweis: genau ein IPAupload, erfolgreicher Prozessabschluss,
  zunächst „processing“, native MacPKG nicht hochgeladen. ReadyToTest wurde durch
  die Warnemail nicht belegt. Die Meldung betrifft iPad-auf-Mac-Kompatibilitätsprüfung,
  nicht den separat gebauten nativen macOS-Binary.
- Tatsächliche Build1-IPA und MacPKG enthalten libswiftCompatibilitySpan.dylib in
  ihrem korrekten Frameworksverzeichnis. IPA enthält iOSarm64/arm64e, native MacPKG
  Mac-/Catalystfähige Slices. Es fehlt nicht schlicht die Dateikopie.
- Beide Hauptbinaries laden @rpath/libswiftCompatibilitySpan.dylib stark, haben
  aber ausschließlich LC_RPATH=/usr/lib/swift, keinen app-lokalen Frameworkspfad.
  So ist die eingebettete Backdeploymentkopie über diese Runpaths unerreichbar.
  Das ist ein konkreter Konfigurationsmangel auch für ältere iPadOS-/macOS-Ziele,
  kein hier bereits ausgeführter echter Geräteabsturzbeweis.
- Neue tatsächliche negative Preflightprobe auf unveränderten Originalarchiven:
  iPadarm64 und nativeMacx86_64 scheitern mit „Embedded dependency has no app-local
  LC_RPATH: libswiftCompatibilitySpan.dylib“. Originale unverändert erhalten.

## Enger Fix

Beide Xcodekonfigurationen setzen SDKbedingt die normalen Frameworks-Runpaths:
iPhone/iPad/Simulator @executable_path/Frameworks, macOS @executable_path/../Frameworks,
jeweils mit inherited. Tatsächliche showBuildSettings für beide Releaseziele geprüft.
Version bleibt0.1.0, Buildnummer ist ausdrücklich2, kein erneuter Build1-Upload.
Preflight prüft Architektur für Architektur die tatsächlich eingebetteten stark
per @rpath geladenen Bibliotheken auf auflösbaren app-lokalen Pfad und passenden
Slice. Systemframeworks/dyld-Cache werden nicht fälschlich nach Dateiexistenz geprüft.
--expected-build erlaubt ausdrückliche Negativprüfung historischer Build1-Artefakte.

Keine manuelle Bibliotheksersetzung, keine SDK-/Plattformstreichung, keine
GPS-/Capabilitytricks, keine Änderung der App-Store-Verfügbarkeit. Ein neuer
signierter Build2 wird zuerst für iPad in getrenntem privatem Pfad erstellt und
lokal exportiert. Altes Build1 bleibt unberührt. Ob die Applewarnung danach im
Processing verschwindet, kann erst eine spätere gesondert freigegebene Delivery
zeigen; der lokale Fix allein ist keine serverseitige Entwarnung.

## Primärquellen

- [Apple Buildsettings: Runpath Search Paths](https://developer.apple.com/documentation/xcode/build-settings-reference)
- [Apple: iOS-Apps auf dem Mac](https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos)
- [Apple: iPad-/iPhoneverfügbarkeit auf AppleSilicon-Macs](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon)
- [AppleDTS: Backdeployment und Frameworks-Runpaths](https://developer.apple.com/forums/thread/730764)

Architektur-/Linking-/Signatur-/Profil-/Build2-Nachweise, exakte CI und unabhängiger
Review folgen tatsächlich nach Ausführung. Keine Betreiberfreigabe oder Runtime-
Kompatibilität allein aus statischen Loadcommands behauptet.
