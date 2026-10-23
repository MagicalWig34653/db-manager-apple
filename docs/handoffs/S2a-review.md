# S2a – unabhängiger Core-/Securityreview

Prüfung am 23.10.2026, QA & Release Engineer. Eigener Branch `review/s2a`,
Worktree `.worktrees/s2a-review`; Produktquelle
`bbbc4e67c6f13b45259983bb52d7108f50ad233f`. Geprüft wurde der gesamte neue Paketdiff
ab `7cbeb38`, einschließlich WIP `e576c05`. Der spätere öffentliche Stand
`8d6fa37b42d1cd5bd795d4783d085367abad5c01` ändert ausschließlich ADR/Handoff;
dessen Präzisierungen ebenfalls lesend geprüft. [Autorenübergabe](S2a.md).

## Urteil und zwingende Grenzen

Keine bestätigten Findings. Das eigenständige S2a-Core-Inkrement ist zur Integration
freigegeben. Die Freigabe gilt nicht für produktive Credentialpersistenz, App-/OS-
Anker, Keychain, ACL-/Sandbox-/FileProtection-/Backupschutz oder reale Geräte.
Ein verpflichtender unabhängiger dauerhafter Anchorprovider ist weiterhin eine
unbelegte Produktvoraussetzung. Ohne dessen separate Abnahme bleibt schreibende
Produktpersistenz gesperrt. Kein Testanker oder stiller InMemory-Fallback im
Librarytarget; synthetische Anbieter nur im Testtarget beziehungsweise in dem erst
temporär gebauten Crash-Prüfexecutable nachgewiesen.

## Format, Kryptografie und Originalquellen

- Alle Format-Lock-Dateien bytegleich gegen den festgelegten Original-S1-Commit
  `1a4eb3c78d22b2fc264b3bce57128d69584735ba` verglichen; Schemahash
  `b688656056fe2e23848ce17149bc817609c7369f230a3f49dd91f05db4d3f4dd`.
  Beide Go-/Swift-Fixtures, AAD, Normativtext und Lizenz erhalten.
- Modelle unverändert; tatsächlicher Codecvergleich gegen S1 zeigt ausschließlich
  KDF-Mutex/Abbruchprüfungen und den internen Create-Einstieg mit vorab gebundener ID.
  Kanonischer ASCII-/JSON-/Tiefen-/Datei-/KDF-Bound vor Argon2, vollständiger HMAC
  vor Eintragsausgabe, AEAD-Kontexte und keinerlei Teilklartextrückgabe geprüft.
- Alle 14 Argon2-Dateien zusätzlich direkt aus dem offiziellen festen Commit
  `f57e61e19229e23c4445b85494dbf7c07de721cb` abgerufen: Bytes und inventarisierte
  SHA256-Werte exakt. Original-LICENSE und Paket-Ressourcencopy gleich; Apache-2.0
  aus ursprünglichem Dualangebot dokumentiert. Eigener Code AGPL-3.0-only,
  keine zusätzlichen entfernten Swift-Abhängigkeiten oder neue Primitive.

## Unabhängig ausgeführte Laufzeitprüfungen

`python3 scripts/check-vault.py` am unveränderten Produktcommit vollständig bestanden:

- 16 tatsächliche Swift-Tests: Faktoren/Manipulation/KDF-/Dateibounds,
  Setup-Rücklesen, Modi/Links/verwaltete Namen, paralleler Rootzugriff, stale CAS,
  Counter-/Generationgrenzen, Rotation, Recoverymigration und Originalerhalt,
  Abbruch/Freigabe, Rollback-/Pending-/Temp-/Finaldateibeschädigung.
- Eigenständiger nativer iPad-Simulator-Zielcompile einschließlich C-KDF bestanden;
  keine App oder Simulator gestartet, kein alter OS-/Gerätelaufzeitnachweis.
- Sechs echte abrupte `_exit(86)`-Childabbrüche an Reservation, Staging, Prepared,
  Rename, Verzeichnissync und Finalisierung. Neue Prozesse erhalten nur exakt
  alten oder vorbereiteten neuen Inhalt, Dateisperre frei, Nutzung nicht erstattet.

Zusätzliche eigene gezielte Unsicherheitsprobe in einer sauberen temporären
Commitarchivkopie, `swift test --filter qaCommittedCAS`: Testprovider führt CAS
tatsächlich erfolgreich aus und wirft anschließend einen I/O-Fehler, getrennt
bei jedem der drei Update-CAS-Schritte. Alle drei Varianten bestanden: kein
gemeldeter Erfolg, keine weiter über `records()` zugänglichen Sessionklartexte,
anschließend exakt alter beziehungsweise neuer Inhalt, reservierte Nutzung bleibt4,
Pending wird aufgelöst. Temporäre QA-Testdatei und Archiv entfernt.

## Geprüfte Sicherheitsgrenzen

Vor jeder geplanten Verschlüsselung vollständige dauerhafte Nutzungsreservierung;
kein Refund bei Fehler/Crash. 2^20-Budget, maximal64 Epochs und UInt-Grenzen vor
Umbruch; Rotation frische Root-/Entrykeys. Beide beibehaltenen Faktoren erneut
nachweisen. Migration mit nur einem überlebenden Faktor erstellt neue Identität,
Root und beide neuen Faktoren; beide vor Persistenz rücklesen, Quelle erhalten.

Descriptorbasierte absolute NOFOLLOW-Pfadtraversierung, UID/0700/0600, reguläre
Dateien und nlink1, exklusiver Root-flock, echtes CAS, Hashvergleich des alten
Stands, exklusive Tempdatei/fsync, tatsächliche Tempbytes vor Rename und Finalbytes
vor finalem CAS geprüft. Recovery akzeptiert ausschließlich vertrauenswürdig
bestätigten alten oder exakt vorbereiteten neuen Hash; Unbekanntes bleibt Fehler.

Gleichzeitiger Restore von Datei und synthetischem Anchor ist ausdrücklich nicht
erkennbar. Die Prozessabbrüche belegen keine Stromausfall-/Hardware-/Netzlaufwerk-
Dauerhaftigkeit; synthetischer Dateianbieter beweist keinen produktiven Anchor.
ACLs und beliebige gleichberechtigte/privilegierte Writer bleiben außerhalb der
belegten Grenze. Keine RAM-/Swap-/SSD-Lösch-, harte DoS-/Sofortabbruchgarantie.

## CI, Dokumentation und Ressourcen

Autoritative GitHub-Abfrage: alle drei Läufe erfolgreich am exakten bbbc4e6-SHA:
[Vault](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901528027),
[Apple](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901527835),
[Dokumentation](https://github.com/MagicalWig34653/db-manager-apple/actions/runs/39901527960).
Die Apple-CI dieses A1-basierten Branches ersetzt keine neue A2-Prüfung.

Dokumentation des Produktstands84/0, Dokumentations-/Diffprüfung dieses Reviewcommits
bestanden. Vollständiger Diff enthält ausschließlich belegte Original-Whitespace-
Besonderheiten in Argon2-LICENSE samt Ressourcencopy sowie encoding.c; diese sind
wegen bestätigter Byteidentität bewusst nicht verändert. Eigene Dateien diffsauber.
Keine Produktänderung; nur dieser Reviewbericht wird committed.

Alle eigenen Prüf-/Crashprozesse, Archive und Scratchverzeichnisse beendet oder
entfernt. Keine Container, Apps, Simulatoren, OS-Rechte oder Keychainitems verändert.
Nächster Schritt: koordinierte Coreintegration einschließlich vollständiger Historie;
S2b/Produktanker/App-/Recovery-/Backupablauf benötigt einen separaten Auftrag und Review.
