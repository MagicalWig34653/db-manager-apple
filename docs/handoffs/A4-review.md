# A4-Review: Nativer MySQL-/MariaDB-Adapter (unabhängig)

Stand: 23.10.2026. Reviewer (nicht Autor). Review-Branch `review/a4-mysql` auf `026d7d7`
(`feat/mysql-adapter`, Basis `84c7504`); Autorenbranch unverändert. ADR-0007 im Root-Repo
(`docs/adr-0007-native-mysql`, `d7c657a`) gelesen, Status Vorschlag, nicht geändert.
Keine Integration nach `main`. Hinzugefügt (nur hier): `scripts/review-a4-fakeserver.py`
(feindlicher Loopback-Fakeserver, synthetisch), `Tests/DBManagerCoreTests/MySQLReviewAttackTests.swift`
(env-gesteuert über `DBM_A4R_DIR`, ohne Variable laufen nur die reinen Parser-Tests).

## Urteil

**Freigabe unter Auflagen für den Adapter als Core-Baustein (nicht UI-eingebunden):** keine
kritischen oder hohen Befunde; die Kernzusage (kein TLS-Downgrade, kein Klartextpasswort ohne
TLS, keine Plugin-Downgrades auf Klartext) hielt allen eigenen Angriffen stand. Vor
Einbindung in die UI sollten F1 und F2 behoben werden. ADR-0007 kann nach Erfüllung der dort
genannten Restkriterien (Versionsmatrix, UI-Entscheidung) angenommen werden; die Annahme ist
Sache des Nutzers.

## Eigene Läufe (23.10.2026, macOS arm64)

| Prüfung | Ergebnis |
| --- | --- |
| `swift test --force-resolved-versions` | 29 + 5 Tests bestanden |
| `scripts/test-mysql.py` (eigene Wegwerf-Container, danach 0 A4-Container) | 34 Tests bestanden, inkl. meiner 3 Zusatztests |
| `check-dependencies.py` | 13 Pins, bestanden |
| `check-docs.py` Apple (156 Dateien) / Root auf ADR-Branch (388 Dateien) | 0 Fehler |
| `xcodebuild` macOS / iOS Simulator (`CODE_SIGNING_ALLOWED=NO`) | BUILD SUCCEEDED |
| `check-icon.sh` | **bei mir bestanden** ("Icon compilation passed") |
| Fakeserver-Angriffe, Mutations-Fuzz (60 000 Läufe) | siehe unten |

check-icon: Der Autorenfehler (actool, fremder Pfad `timetrack-apple-wt`) ist damit ein
Hostproblem seiner Umgebung (stale actool-/Simulatorcache), kein A4-Defekt. Nebenbefund:
`swift test` scheiterte bei mir zeitweise mit "resource fork ... detritus not allowed" beim
Codesign (Finder-Metadaten im `.build`, Pfad mit Leerzeichen/iCloud-nahe); `xattr -cr .build/out`
behob es. Ebenfalls Host, nicht A4.

## Ergebnisse je Prüfpunkt

**(1) TLS.** Fakeserver ohne `CLIENT_SSL` im Greeting: `mysqlTLSRequired`, Server erhielt
**0 Byte** vom Client. Code: Greeting, Capability-Check, SSLRequest, TLS-Handshake, erst dann
Benutzer/Auth (`MySQLConnection.handshake`); es gibt keinen Pfad, der ohne `config.tls` und
Fehlschlag TLS überspringt (nil nur durch ausdrückliche Loopback-Option). Abgelehnt: abgelaufenes
Zertifikat (Serverlog: Alert certificate expired), Zertifikat fremder CA, falscher Hostname,
DNS-Zertifikat bei IP-Ziel, Server-CA nicht im Systemspeicher. Positiv: IP-SAN-Zertifikat bei
IP-Ziel wird akzeptiert, bei Hostname `localhost` abgelehnt. Klartextoption: nur Loopback
(`localhost`, `127.x.y.z`, `::1`), Kombination mit CA abgelehnt (Unit-Test, Code geprüft).

**(2) Passwort.** Full-Auth (0x04) über TLS: Server erhielt `Passwort\0`, nur im TLS-Kanal.
Ohne TLS (Loopback-Option): Abbruch `mysqlUnsupportedAuth`, **0 Byte** nach der Anforderung.
AuthSwitch auf `mysql_clear_password`, `sha256_password`, `client_ed25519`, `mysql_old_password`
wird abgelehnt (bei Klartext-Switch ohne TLS 0 Byte gesendet; mit TLS keine Antwort). Scrambles
gegen Referenzvektoren und beide Live-Server (MariaDB/native, MySQL 8.4/caching_sha2) korrekt.
Fehlertexte: feste Texte plus Code; `errpacket`-Test mit "Secret"/Pfad in der Servermeldung
lieferte nur `mysqlFailed(1064)`.

**(3) Parser.** Übergroßer Header (0xFFFFFF vs. Limit), falsche Sequenz, Spaltenzahl 2^64-1 und 0,
Zelllänge 2^64-1 und 2^63, zu kurze Zeile, LOCAL-INFILE-Anforderung, endloser Zeilenstrom
(auf `maxRows` begrenzt, truncated), 60-kB-Zeilen (resultTooLarge), Byte-für-Byte-Tröpfeln,
hängender Server (Deadline): kein Absturz, kein Hänger, Task endet. Mutations-Fuzz der
Parser (Greeting, Spaltendefinition, Längenkodierung, Assembler, Wertekonvertierung; 60 000
Mutationen) ohne Trap. Fragmentierung per Unit-Test: 16-MiB-Split mit 1-MB-Chunks korrekt
zusammengesetzt, Sequenz läuft weiter, Summenlimit über Fragmente greift. Produktiv ist ein
Split nie erreichbar (`packetLimit` < 16 MB), der Code ist also konservativ.

**(4) Werte.** Live bestätigt (Autorentests nachgelaufen und gelesen): DECIMAL(40,20),
BIGINT UNSIGNED max, DATETIME(6), NULL vs. leer, BLOB base64, utf8mb4 inkl. Emoji. Ungültiges
UTF-8 in Textspalte führt zu `invalidText` für das ganze Ergebnis (Fakeserver bestätigt, kein
Absturz); konservativ, aber kein Teilergebnis.

**(5) Abbruch.** Autor-Livetests (Deadline, Task-Abbruch, Verschwinden der Abfrage, READ ONLY
blockt INSERT, mutierende Funktion, DDL) bei mir erneut grün. Nur gegen MariaDB belegt, siehe F6.

**(6) Injection.** Katalog-SQL statisch; `selectSQL` verdoppelt Backticks, NUL-Bytes werden vor
dem Senden abgelehnt; Live mit `odd`db`.`odd`table` grün. Kein Befund.

**(7) Concurrency.** `@unchecked Sendable` mit Locks; Zugriffe auf `assembler` nur sequentiell
durch einen Task; `forceClose` threadsicher. Der Gate hält über den Kill-Task kurzzeitig eine
Selbstreferenz, die mit Taskende endet (kein dauerhafter Zyklus). Kein Befund außer F4.

**(8) Lizenz/Doku.** Keine neue Paketabhängigkeit (`NIOPosix`, `NIOTLS` aus gepinntem
swift-nio, Pins unverändert, geprüft). Handoff ist überwiegend ehrlich und nennt selbst die
Lücken (kein Fake-Server-Test, kein abgelaufenes Zertifikat, kein Fuzz, nur eine Version je
Familie). Diese drei Lücken sind jetzt geschlossen (Fakeserver, abgelaufen, Fuzz-Basis); die
Versionsmatrix bleibt offen. Kleinigkeit: "kein SQL im Fehler" gilt für den Adapter, nicht für
`dump(MySQLSettings)` (F3).

## Befunde

**F1 (Mittel, Härtung) Pre-TLS-Bytes können nach dem Handshake als Daten gelesen werden.**
Beleg: `handshake` prüft nach dem SSLRequest nur `assembler.isEmpty`; Bytes, die zwischen
Greeting und Einbau des `NIOSSLClientHandler` eintreffen, liegen in `MySQLInboundHandler.chunks`
und werden von `next()` nach dem TLS-Aufbau als vermeintlich entschlüsselte Daten geliefert
(klassische STARTTLS-Antwortinjektion). Dynamischer Test (20 Läufe je Zeitpunkt, 5 Zeitpunkte,
plus Injektion vor dem SSLRequest): eingeschleuste Klartextpakete mit gefälschtem OK und
Fake-Katalog wurden **nie als Erfolg akzeptiert** (alle `mysqlProtocolError` oder
`mysqlConnectionFailed`), weil Sequenz und Handshake-Zustand nicht passten; ein Angreifer mit
passender Sequenzfolge ist nicht ausgeschlossen, aber nicht gezeigt. Fix: vor dem
TLS-Handler die Eingangswarteschlange leeren bzw. erzwingen, dass sie leer ist (Fehler
`mysqlProtocolError`), und `chunks` nach TLS-Erfolg verwerfen; Regressionstest mit
`inject:*` des Fakeservers.

**F2 (Niedrig) `KILL QUERY` nutzt die Thread-ID aus dem unauthentifizierten Greeting.** Ein
Angreifer, der Bytes nur durchreicht, kann die ID ändern; wirkt nur auf Abfragen desselben
Kontos. Fix: `SELECT CONNECTION_ID()` nach authentifizierter TLS-Sitzung.

**F3 (Niedrig) Passwort in Standard-Reflexion.** `MySQLSettings` und `MySQLConnectionConfig`
haben keine eigene Beschreibung; `dump`/`String(reflecting:)` zeigt das Passwort. Der Code
loggt nirgends (per Suche belegt), aber die Zusage im Kommentar ist nur Absicht. Fix:
`CustomStringConvertible`/`CustomDebugStringConvertible`/`CustomReflectable` mit Schwärzung
und ein Test.

**F4 (Niedrig) AuthSwitch von `caching_sha2_password` auf `mysql_native_password` erlaubt.**
Nur innerhalb verifizierten TLS und mit Scramble statt Klartext, daher kein Downgrade auf
Klartext; als Schwächung durch einen kompromittierten Server dokumentieren oder auf das
Greeting-Plugin beschränken.

**F5 (Niedrig) Fehlerüberdeckung.** Bei `resultTooLarge`/`invalidText` ruft der Adapter
`KILL`; schlägt es fehl, wird `cancellationUnconfirmed` statt der Ursache gemeldet (im
Fakeserver-Test sichtbar). Fehlerbild irreführend, sicherheitlich unkritisch. Zudem Stall bis
5,2 s bei 3 s Timeout (KILL-Frist 2 s).

**F6 (Niedrig/Info) Lücken.** Abbruchprobe nicht gegen MySQL 8.4; Katalog scheitert ab
10 000 Objekten (`resultTooLarge`); ERR-Paket anstelle von Spaltendefinition/EOF wird als
Protokollfehler statt Serverfehler gemeldet; ein Fakeserver-Lauf (`drip`) endete mit
`mysqlConnectionFailed`, Ursache nicht ergründet (schließt sicher, kein Hänger). Lesemodus
bleibt keine Sandbox (wie dokumentiert). `localhost` wird vom System aufgelöst (Resolver
vertraut).

## Reproduktion

`python3 scripts/review-a4-fakeserver.py <dir>` starten, dann
`DBM_A4R_DIR=<dir> swift test --force-resolved-versions --filter Review`; Ergebnisse in
`<dir>/report-*.txt` und `<dir>/log-*.json` (Serverseite). Die Logs werden erst nach der
Client-Wartezeit geschrieben.
