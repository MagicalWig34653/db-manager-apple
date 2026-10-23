# A-TF1 – freigegebene Integration und private Artefaktsicherung

23.10.2026. Eigener Branch release/atf1-integration-20261023 im Worktree
.worktrees/release-atf1 ab Apple-maine50d745. Konkrete Leadfreigabe nach unabhängigem
Source-/Artefakt-/CIreview und exklusiver Transfer der AppleSTATUS-/Plan-Dateien.
Der Nutzer hat nach Beginn den Erstupload auf TestFlight ausdrücklich autorisiert.
Ein eigener Delivery-Agent übernimmt ihn; dieser Releasekoordinator führt keine
parallelen Upload-/ASCmutationen aus, kein App-Store-Releaseauftrag.

## Provenienz

- Vollständiges Feature bis6551a8aff75b80270562771354f21de54fcbea6d mit
  b702051, Diagnose de58e92 und Hostfix645c8c1b2dbd401410cdaf42afc0b221770f322e
  als7f5282e übernommen.
- Vollständiger unabhängiger Review bis7e6619e5d071ed7afdcd7d7ccaa11e3a81190099
  als9a15581 übernommen. Frühere Fehlserie und kontrollierter erfolgreicher Hostfix
  bleiben ausdrücklich getrennt dokumentiert.
- App-/Icon-/Xcode-/Sources-/Package-/Distributionbytes zum bereits geprüften
  b702051 exakt identisch. Keine neue produktive Änderung oder Archivierung.
- Alle drei exakten645-CIs erfolgreich; der Mainpush startet eine eigene neue
  Matrix, noch kein vorweggenommener Erfolg. Details im [Review](A-TF1-review.md).

## Private dauerhafte Kopien

Explizit beauftragt: finale iPadIPA, native universelle MacPKG und beide zugehörigen
Originalarchive in einem privaten lokalen Developer-Unterordner für0.1.0Build1.
Keine vorhandenen abweichenden Dateien überschrieben. Neue Exportdateien0600,
privates Versionsverzeichnis0700; Archiv-Executebits/Symlinks erhalten, private
Ancestraldirectory schützt den gesamten Inhalt. Exakte persönliche Pfade wurden
nur der Koordination für den Eigentümer genannt, nicht ins Repository geschrieben.

- DBManager-iPadOS.ipa SHA256
  cb9be4a57944c5d1a1395ffd590ce7974a6c478fb2decc6fee92cc53089fb34e,
  14725374Bytes.
- DBManager-macOS.pkg SHA256
  2ef0711e0a2fbc867710007b73bec2ae08acfb2f4628c028a32e8cd5c37e853b,
  22744566Bytes.
- DBManager-iPadOS.xcarchive und DBManager-macOS.xcarchive: jeder reguläre Dateihash,
  relative Verzeichnisse und Symlinkziele vor/nach Kopie identisch; private Receipt
  enthält vollständige Dateibaummanifeste/aggregierte SHA256 und Bytezahlen.
- Private lokale README nennt Plattformen, Build-/Reviewsource und offene
  Betreiber-/Uploadgates. Keine Profile-/Keybytes im öffentlichen Receipt oder Git.

Originale temporäre Exporte/Archive weder geändert noch entfernt. Kein neues
Signing-/Account-/Keychain-/OSrechteingreifen, kein Upload oder Installieren.

## Tatsächliche begrenzte Releasechecks

13 Rootpins/Originaltexte, Shell-/Python-Syntax, Source-/Assetbytevergleich und
Feature-/Review-Ancestry bestanden. Sourceexporte gegen öffentliche Quittung und
private Kopien mit SHA/Bytegröße geprüft. Beide kopierten Archive mit tatsächlicher
Appidentität de.linolaske.dbmanager/0.1.0Build1 und strikter codesign-Prüfung bestanden.
Dokumentation vor dem abschließenden Handoff142/0, abschließend143 Dateien/0Fehler.
Keine alte native Vollmatrix wiederholt, keine neuen Geräte-/Runtime-/Storebeweise.

## Fortsetzung und Ressourcen

Keine lokalen Build-/Signing-/Compiler-/Deployjobs offen, keine Container angelegt.
Gewollte private Benutzerartefakte und Originale bleiben erhalten. AppleSTATUS/Plan
für diesen Checkpoint exklusiv beim Releasekoordinator, andere Owner schreiben
nicht parallel. Nach Veröffentlichung exakte Main-SHA/CI-IDs und private Pfade an
Root melden; weitere Publikation nur nach konkreter Freigabe. Der autorisierte
Erstupload und tatsächliche TestFlightverarbeitung sowie Betreiberangaben werden
vom separat beauftragten Delivery-Agent bearbeitet.
