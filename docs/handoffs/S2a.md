# S2a: eigenständiger nativer Tresorkern

Stand: 23.10.2026. Fortsetzung ausdrücklich bis10:00 Europe/Berlin (=08:00UTC).
Branch `feat/vault-core`, Basis `7cbeb38`; lokaler Unterbrechungs-WIP `e576c05`.
**Autorenkandidat, unabhängige QA offen, keine produktive Credentialpersistenz.**

## Ergebnis und Besitz

Neues [DBManagerVault-Paket](../../Packages/DBManagerVault/README.md),
[ADR-A003](../decisions/ADR-A003-vault-core.md), eigene Vault-CI und
`scripts/check-vault.py`. Keine App-/Xcode-/Root-Package-/DBManagerCore-/A2-
Produktdateien geändert. Die zusätzlich delegierten Apple-STATUS/ARBEITSPLAN und
unabhängige A2-Reviewdoku wurden getrennt nach Main integriert; keine Corefreigabe.

Actor-Session, v1-Reader, Passwort-/Recoverywege und neue-Faktoren-Migration,
Lock/Update/Rotation, verwaltete Dateinamen/Roots, private Modi, Linksperren,
flock/CAS/atomare Ablage mit Hash-Rücklesen und Pending-Recovery sind implementiert.
Reservierungen erfolgen vor jeder geplanten Verschlüsselung; kein Refund bei
Fehler/Abbruch/Crash. 2^20-Nutzungsbudget, UInt-Überläufe und maximal64 Epochs stoppen
vor Umbruch. Rotation behält alte Faktoren nur nach beiden Nachweisen. Bei Verlust
ist Migration mit einem überlebenden Faktor zu neuer Identität/Root/Passwort/
Recovery möglich. Das neue Passwort darf den alten Tresor nicht öffnen. Beide neuen
Wege vor Persistenz tatsächlich entschlüsseln, Original erhalten. Kein Nachbilden
unbekannter alter Faktoren oder ungeprüftes Rücksetzen importierter Rootnutzung.

## Format, Herkunft und Lizenzen

Unveränderte v1-Bytes aus `1a4eb3c78d22b2fc264b3bce57128d69584735ba`, Handoff
`03bd3f40e436efe44dbbdcbbcbb6245e285ad4bf`. Schemahash
`b688656056fe2e23848ce17149bc817609c7369f230a3f49dd91f05db4d3f4dd`.
Beide öffentlichen synthetischen Go-/Swift-Fixtures und feste AAD enthalten.
[Format-Lock](../../Packages/DBManagerVault/format-lock.json),
[Lizenzinventar](../../Packages/DBManagerVault/LIZENZEN.md).

Argon2-C bytegleich vom offiziellen Pin
`f57e61e19229e23c4445b85494dbf7c07de721cb`,14 geprüfte Originalhashes und volle
Original-LICENSE. Apache-2.0 aus ursprünglichem Dualangebot gewählt; keine eigene
Primitive. System-CryptoKit/Security/Foundation/Darwin, keine entfernten Swiftdeps,
daher kein künstliches Package.resolved. Lizenztexte als Paketressourcen und
Runtimezugriff geprüft; kein heute existierendes Vault-Appbundle behauptet.

## Tatsächliche reproduzierbare Prüfungen

```sh
python3 scripts/check-vault.py
python3 scripts/check-docs.py
git diff --check e576c05
```

Frischer vollständiger Autorenlauf am23.10.2026 bestanden:

- **16 Swift-Tests** aktiv: beide S1-Entsperrwege/Go-/Swift-Fixtures, AAD,
  Manipulation/Trunkierungen/KDFgrenzen, Setup-Rücklesen, Payload-/Dateibounds,
  private Modi, Symlinks/Hardlinks/Namensgrenzen, konkurrierender Rootzugriff,
  stale CAS, Counter-/Generationerschöpfung, Rotation, Recoverymigration bei
  Passwortverlust, Originalerhalt, Abbruch/Freigabe und bekannte Crashzustände.
- Frischer macOS-Paketbuild/Tests und nativer
  `arm64-apple-ios17.0-simulator`-Compile einschließlich C-KDF bestanden.
  Keine App/Simulator gestartet; kein Zielgeräte-/Alt-OS-Laufzeitnachweis.
- **Sechs echte abrupte Prozessexits** mittels `_exit(86)` an Reservation/Staging/
  Prepared/Rename/Dirsync/Finalisierung. Neue Prozesse öffnen nur den alten oder
  exakt vorbereiteten neuen Inhalt; flock frei, Reservierungen stets verbraucht.
  Der synthetische Dateianbieter wird nur im temporären Crashprüfexecutable gebaut,
  nicht im Librarytarget oder als produktiver Fallback.
- Format-/Fixturepins,14 Original-Argon2hashes und Quell-/Ressourcenlizenzen geprüft.
  Kein Geschwisterrepo nötig. Gleichzeitiges Zurückspielen von Datei **und**
  synthetischem Anker wird bewusst nicht erkannt und ist als Grenze getestet.

Bei Wiederaufnahme fand die enge Selbstprüfung beschädigte Tempbytes nach Staging:
zuvor konnte Rename ohne passenden Inhalt als Erfolg zurückkehren. Neue Regression
zuerst mit3 Assertions rot. Fix: tatsächliche Tempbytes vor Rename und endgültige
Dateibytes vor unabhängigem finalem Anker-CAS rücklesen/vergleichen. Temp- und
Enddateibeschädigung sind danach grün. Kein Commitversprechen bei unklarem Fehler.

Archivcheckpoint und öffentliche CI-IDs folgen nach Kandidatencommit gesondert;
bis dahin kein behaupteter Archiv-/CI-Erfolg. Format-/Lizenz-/Anker-/Writer-/Counter-/
Recoveryprüfung durch unabhängige QA bleibt vor jeder Coreintegration erforderlich.

## Grenzen und Ressourcen

**Kein produktiver Anker implementiert oder getestet.** Keine Keychainitems/ACLs,
OS-Rechte oder Truststores verändert; keine signierte Zugriffsgroup bewiesen.
ThisDeviceOnly allein ist kein Nichtzurückrollbarkeitsnachweis. Kein stiller
InMemory-Fallback, kein Zählervertrauen bei gemeinsamem Restore. Provider ist
zwingende unabhängige Vertrauensannahme; ein Protokoll macht Dateispeicher nicht sicher.

Private lokale Roots koordinieren kooperative Instanzen. Keine Racefreiheit gegen
beliebige gleichberechtigte/privilegierte OSwriter oder nachträgliche Manipulation.
FileProtection/Sandbox/Backup-/Restorepolitik, Stromausfall/Hardware/Netzlaufwerke
bleiben offen. Argon2 ist nicht kooperativ abbrechbar; ein KDF-Aufruf je Prozess,
keine harte Wartezeit-/Gesamtprozess-RAM-/DoSgarantie. Lock verwirft Referenzen,
keine RAM-/SSD-/Swap-/Backup-Löschzusage. Beide Faktoren oder Ciphertexte verloren:
Datenverlust. Alte Kopien bleiben mit alten Faktoren lesbar; echte DBcredentials
müssen am Ziel rotiert werden.

Eigene Tests nutzen nur zufällige temporäre Verzeichnisse/Prozesse und finally-
Cleanup. Keine Dockerressourcen, Apps oder Simulatoren gestartet. Verbliebene eigene
Caches werden nach dem Archivlauf entfernt, laufende Jobs im Abschlusscheckpoint
angegeben. Nächster Schritt: unabhängige S2a-QA; S2b/App-/Anchor-/Backupablauf und
CloudKit/Passkey/Teams/SSH gehören nicht zu diesem Kandidaten.

## Abschließender Archiv-/CI-Checkpoint

Semantischer Codekandidat **`bbbc4e67c6f13b45259983bb52d7108f50ad233f`**, nach
Unterbrechungs-WIP `e576c05`, öffentlich auf `origin/feat/vault-core`. Zur späteren
Integration gehört der gesamte Paketdiff ab `7cbeb38`; nicht nur der Folgecommit.
Die unabhängige QA prüft diesen eingefrorenen Stand; danach keine Produktbytes
verändert. Dieser Folgecheckpoint ergänzt ausschließlich Prüf-/Grenzendokumentation.

**Frisches `git archive bbbc4e6` am23.10.2026 tatsächlich vollständig bestanden:**
aus temporärer sauberer Archivkopie `python3 scripts/check-vault.py` und
`python3 scripts/check-docs.py`; 16 Tests, nativer iPad-Zielcompile, sechs echte
abrupte Childexits, Pins/Originaltexte und84 Dokumentdateien/0Fehler. Keine lokalen
Builddateien, Caches oder Geschwisterrepos waren dafür nötig. Temporäre Archivkopie,
Buildscratch und eigene zusätzliche KDF-Testcaches anschließend entfernt.

Öffentliche Jobs am exakten Codekandidaten:

- [Dokumentation39901527960](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901527960): erfolgreich.
- [Native Vault Core39901528027](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901528027): abschließend erfolgreich am exakten Codekandidaten.
- [Apple-Build39901527835](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901527835): abschließend erfolgreich am exakten Codekandidaten. Dieser isolierte Branch beruht auf A1; keine neue A2-Prüfung daraus ableiten.

Alle drei öffentlichen CIs abschließend grün; verbleibend ist die unabhängige QA. **Keine
eigenen lokalen Prüfprozesse, Fixturecontainer oder Simulatoren aktiv.**
UID/0700/0600-Modusbits sind geprüft; erweiterte ACLs, tatsächlicher abgeschotteter
Appcontainer und OS-Anker nicht. Vor Setupbestätigung existieren bereits nicht
geheime reservierte Ankermetadaten, aber noch keine Tresornutzdatei. Diese
Präzisierung ist keine produktive Anchorimplementierung. Nächster Schritt: QA-
Findings/CIs durch koordinierende Rolle auswerten; kein weiteres Feature begonnen.


## Delegierte Releaseintegration auf bestehendem A2-main

23.10.2026, eigene `.worktrees/vault-release` / `release/vault-core`, Basis
`3c92f974aa6d1c3056b25e3bc9ec5b0d0cb9f161`. Konkrete Leadfreigabe nach unabhängigem
Review, kein Selbstreview als Abnahmeersatz. Vollständige Provenienz:

| Geprüfte Quelle | Integrationscommit |
| --- | --- |
| WIPe576c05 |1023774|
| Produktbbbc4e67 |46badd1|
| ADR-/Archivhandoff4257cde |5e39156|
| CI-Handoff8d6fa37 |ca9b57f|
| Unabhängiger Reviewbe121457 |4b3ffdc|

Gesamtes Paket, Vaultscript und Vault-CI per Gitdiff bytegleich zur freigegebenen
Quelle8d6fa37. `Sources`, Root-Package/Locks und Xcodeprojekt bytegleich zum
vorherigen A2-main3c92f97. Nur ADR-/Status-/Integrationsnachweise zusätzlich;
ADR-A003 akzeptiert ausschließlich den begrenzten Core, keine App-/Anchorfreigabe.

Am kombinierten Integrationsbaum tatsächlich bestanden:

- `python3 scripts/check-vault.py`:16 Tests, iPad-Zielcompile, sechs echte
  Prozessabbrüche, alle Format-/Fixture-/14-Argon2pins und Originaltexte.
- `sh scripts/check-apple.sh`:17 Core-/5 Appprüfungen, dabei sechs Livetests ohne
  Fixtureumgebung ausdrücklich übersprungen; zusätzlich1.008 Datum-/4.032
  Timestampvektoren,13 Pins und vollständige Originalnotices, macOS-/generischer
  iPad-Appbuild einschließlich Originaltexte und Info.plist, Dokumentation125/0.
- Keine erneute echte PG-Livematrix, UIautomation, Signing-/OS-/Gerätefreigabe.
  Die neue Bibliothek wird weiterhin nicht von der App oder Root-Package eingebunden.

Eigene parallele Prüfläufe und Scratchverzeichnisse beendet/entfernt. Main-CI
startet nach der freigegebenen Veröffentlichung und wird separat exakt zugeordnet;
kein vorweggenommener kombinierter CI-Erfolg. Nicht zurückrollbarer Produktanker
und spätere persönliche Credentialpersistenz bleiben gesonderte S2b-Gates.
