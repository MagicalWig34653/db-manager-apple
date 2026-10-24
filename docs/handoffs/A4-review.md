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

## Nachreview (24.10.2026) zu `4faa2e6`

Geprüft: `feat/mysql-adapter` @ `4faa2e6` (in diesen Branch gemerged), Läufe nacheinander
bei hoher Hostlast. Urteil: **freigabefähig** als nicht UI-eingebundener Core-Baustein; keine
neuen kritischen oder hohen Befunde. Offen nur die unten genannten niedrigen Punkte.

Läufe: `swift test` mit `DBM_A4R_DIR` (Fakeserver gegen die gefixte Version): 37 + 5 Tests
bestanden; `scripts/test-mysql.py` (Wegwerf-Container, danach 0 Container): 37 + 5 bestanden,
inkl. Abbruchprobe gegen MariaDB und MySQL 8.4; `check-dependencies.py` 13 Pins;
`check-docs.py` 157 (Apple) / 388 Dateien (Root-ADR-Branch), 0 Fehler; `xcodebuild` macOS und
iOS Simulator BUILD SUCCEEDED. Erneut nur Hostproblem: Codesign-"detritus" beim ersten Build,
behoben durch `xattr -cr .build/out`.

| Befund | Status | Beleg |
| --- | --- | --- |
| F1 Pre-TLS-Queue | geschlossen | Code: `requireNoQueuedData()` vor dem Handler-Einbau, nochmals auf dem Eventloop unmittelbar davor (atomar zur Lesesicht) und nach dem TLS-Aufbau. EmbeddedChannel-Test schlägt fehl, wenn der Aufruf fehlt (prüft den Guard selbst, nicht den Handshake-Aufruf). Fakeserver `inject:*` (je 20 Läufe, 6 Zeitpunkte): nie akzeptiert; bei Injektion direkt nach dem Greeting jetzt überwiegend `mysqlProtocolError` (früher auch Verbindungsfehler). |
| F2 Thread-ID | geschlossen | `SELECT CONNECTION_ID()` nach Anmeldung; `threadID` aus dem Greeting entfernt. |
| F3 Redaktion | geschlossen | Test prüft `describing`, `reflecting`, `dump` auf Host, Benutzer, Passwort. |
| F4 Plugin-Wechsel | geschlossen, Restschwäche ehrlich | Wechsel nur bei aktivem TLS; Klartext-Switch und Nicht-Greeting-Wechsel ohne TLS abgelehnt (Fakeserver: 0 Byte). Kompromittierter zertifikatsgültiger Server kann ein Scramble (kein Klartext) eines schwächeren Plugins verlangen; im Handoff dokumentiert, ebenso dass kein Einzeltest existiert. |
| F5 Ursache | geschlossen | Fakeserver zeigt jetzt `resultTooLarge`/`invalidText` statt `cancellationUnconfirmed`; Unit-Test `failure(...)`. |
| F6 | geschlossen | ERR in Spalten/EOF wird Serverfehler; Abbruchprobe läuft gegen beide Server; Katalogobergrenze dokumentiert (Paginierung offen). |

Regression: keine gefunden; alle früheren Angriffsergebnisse (TLS-Downgrade 0 Byte, Zertifikats-
und Hostnamenfälle, Full-Auth nur über TLS, Parser-Fälle) unverändert. Doku: Handoff beschreibt
Fixes sachlich; der dortige Hinweis, der Fakeserver-Lauf sei nach den Fixes nicht wiederholt
worden, ist durch diesen Nachreview erledigt.

Neue Befunde:

**N1 (Niedrig) Deadline wird bei hängendem Server während `CONNECTION_ID` überschritten.**
Fakeserver `mal_idstall` (antwortet nie auf `SELECT CONNECTION_ID()`), Timeout 3 s: Rückkehr
mit `canceled` nach ca. 10,5 s (zum Vergleich hängende Nutzabfrage: 5,2 s). Terminiert, aber
ohne Garantie der Nutzerfrist; der Pfad `authenticatedConnectionID` läuft vor dem
Cancel-Handler und ohne eigenes Zeitlimit (`timeout: 5` in den Limits wird von `query` nicht
erzwungen). Fix: Abfrage in den abbrechbaren Bereich ziehen bzw. am Gate per Frist begrenzen.

**N2 (Info)** Der Fakeserver-Harness musste angepasst werden (Antwort auf `CONNECTION_ID`,
neuer Modus `idstall`); Änderungen liegen im Review-Branch.

## Zweiter Nachreview (24.10.2026) zu `227b44d` (explizite Transportmodi, N1-Fix)

Geprüft: `git diff 575c1d9..227b44d`, in diesen Branch gemerged; ADR-0007 auf `740d762`
(Abschnitt 3a). Läufe nacheinander nach `uptime`. Urteil: **freigabefähig** (weiterhin als nicht
UI-eingebundener Core-Baustein); keine kritischen oder hohen Befunde, zwei niedrige Doku-Punkte.

Läufe: `swift test` mit `DBM_A4R_DIR` (Fakeserver): 38 + 5 bestanden; `scripts/test-mysql.py`:
38 + 5 bestanden, danach 0 Container; `check-dependencies.py` 13 Pins; `check-docs.py` 157 / 388
Dateien, 0 Fehler (Apple / ADR-Branch); `xcodebuild` macOS und iOS Simulator BUILD SUCCEEDED.

| Punkt | Ergebnis | Beleg |
| --- | --- | --- |
| (a) Server ohne `CLIENT_SSL` in `.verifiedTLS` und `.unverifiedTLS` | geschlossen | Fakeserver `nossl`: je **0 Clientbytes**, `mysqlTLSRequired`; nur `.plaintext` sendet (96 Byte, erwartungsgemäß, Scramble). Der Guard `if let context = config.tls` prüft `CLIENT_SSL` vor dem ersten Authentifizierungsbyte unverändert. Inject-Läufe (6 Zeitpunkte, je 20, abwechselnd verifiziert/unverified): nie akzeptiert. |
| (b) `.plaintext` sendet nie Klartextpasswort | geschlossen | `plain_fullauth` (0x04): `mysqlUnsupportedAuth`, 0 Byte danach; `plain_switch_clear`: abgelehnt, 0 Byte; AuthSwitch auf `sha256_password`, `client_ed25519`, `mysql_old_password`, `mysql_clear_password` abgelehnt (Antwortfunktion liefert nur für zwei Scramble-Plugins). Live: frisches caching_sha2-Konto ohne TLS abgelehnt, über TLS ok. |
| (c) Kein stilles Abschwächen | geschlossen | Initializer-Default `.verifiedTLS` (Test); `MySQLSettings` ohne Codable/Decoding; `configuration` verzweigt nur über den gesetzten Modus; der Kill-Kanal übernimmt `security` des Hauptkanals; alter Loopback-Name im Code nicht mehr vorhanden (nur als "überholt" im Handoff). CA-Datei mit `.unverifiedTLS`/`.plaintext` wird abgelehnt (Test). |
| (d) `.unverifiedTLS` | korrekt | Server sah TLS 1.3 (`TLS_AES_256_GCM_SHA384`) und erhielt die Anmeldung erst danach, bei abgelaufenem Zertifikat, fremder CA und falschem Hostnamen; kein SNI/Hostname übergeben (`serverName == nil`, Test). Mindestens TLS 1.2 bleibt (Test). Bei Full-Auth erreicht das Klartextpasswort die unverifizierte Gegenstelle (Fakeserver bestätigt) -- wie dokumentiert. `mysql_clear_password`-Switch auch hier abgelehnt. |
| (e) `max_execution_time`/`max_statement_time` +1 s | korrekt | Wert = Clientfrist + 1000 ms, MariaDB in Sekunden (Dezimal), MySQL in ms; weiter `try?` best effort. MySQL-Limit gilt nur für SELECT (Schreib-/DDL-Anweisungen unberührt, Katalog ist ein SELECT); MariaDB-Limit gilt für alle Anweisungen, nun 1 s später als zuvor -- keine neue Nebenwirkung. Clientfrist plus `KILL` greift zuerst. |
| N1 | geschlossen | `idstall` bei 3 s Frist: `canceled` nach 3,07 s (vorher 10,5 s). |
| (f) Doku | ehrlich, zwei Lücken | ADR 3a und Handoff nennen Folgen für beide Modi offen, auch Full-Auth-Klartext im unverifizierten TLS, nicht implementierten RSA-Austausch und nicht getestete Zwischensystem-Szenarien. |

Neue Befunde:

**N3 (Niedrig, Doku)** ADR-0007 3a nennt Offline-Ratenangriffe auf den Scramble nur bei Modus (2);
sie gelten in Modus (3) ebenso, und dort kann ein aktiver Angreifer per AuthSwitch zusätzlich ein
schwächeres unterstütztes Plugin (SHA-1-Scramble, `mysql_native_password`) erzwingen, weil der
Wechsel ohne TLS jetzt erlaubt ist. Kein Klartextleck, aber stärkeres Material für Offline-Angriffe.
Fix: im ADR ergänzen oder in `.plaintext` den Wechsel auf das Greeting-Plugin beschränken.

**N4 (Niedrig, Doku)** ADR-0007 Abschnitt 6 nennt noch das Kriterium "UI-Darstellung der
Entwicklungsoption" und Abschnitt 3 Regeln 1/3 stehen unverändert neben 3a; 3a nennt sie
ersetzt, die Kriterienliste ist aber nicht angepasst (jetzt: UI-Darstellung der Warnstufen).

Hinweis: Der Reviewer-Harness wurde erweitert (Unverified-Fälle, Cipher-Log); die
Fakeserver-Ergebnisse im Handoff des Autors ("nossl je 0 Clientbytes", idstall 3,1 s) sind damit
unabhängig bestätigt.

## Dritter Nachreview (24.10.2026) zu `293a949` (RSA-Austausch, Full-Auth in allen Modi)

Geprüft: `git diff 227b44d..293a949`, `feat/mysql-adapter` in diesen Branch gemerged; Root-ADR auf
`956298e` (Status Akzeptiert). Läufe nacheinander nach `uptime`. Urteil: **freigabefähig** (weiter als
nicht UI-eingebundener Core-Baustein); keine kritischen oder hohen Befunde, zwei niedrige/Info-Punkte.

Läufe: `swift test` mit `DBM_A4R_DIR` (Fakeserver, erneut nach der Änderung): 41 + 5 bestanden;
`scripts/test-mysql.py`: 41 + 5 bestanden, danach 0 Container (Live gegen MySQL 8.4: frische Konten über
`.plaintext`/RSA, `.unverifiedTLS`, `.verifiedTLS`, falsches Passwort abgelehnt); `check-dependencies.py`
13 Pins; `check-docs.py` 158 / 388 Dateien, 0 Fehler (Apple / ADR-Branch); `xcodebuild` macOS und iOS
Simulator BUILD SUCCEEDED. Hostartefakt wie zuvor: Codesign-"detritus" im ersten `swift test`-Anlauf,
`xattr -cr .build/out` behebt es.

| Punkt | Ergebnis | Beleg |
| --- | --- | --- |
| (a) RSA-Pfad | korrekt | Unabhängige Gegenstelle (Python `cryptography`, Fakeserver `plain_rsa`): Schlüsselanfrage war exakt `0x02`; Ciphertext 256 Byte; mit **OAEP-SHA1/MGF1-SHA1** entschlüsselt und mit der 20-Byte-Nonce XOR zurück ergibt `Passwort\0` (`decrypted_ok: true`). Gesamter Clientverkehr (361 Byte) enthält das Klartextpasswort **nicht**. Nonce stammt aus Greeting bzw. AuthSwitch (nach Plugin-Wechsel aktualisiert). Schlüsselprüfung: Schlüssel 1024 Bit -> `mysqlUnsupportedAuth`, danach **kein weiteres Clientbyte** (Mitschnitt 101 Byte = Hello, Auth, 0x02); Müllschlüssel -> `mysqlProtocolError`, ebenfalls nichts mehr gesendet. DER-Leser: nur definite Längen bis 2 Byte, Längenprüfung gegen Restpuffer, Gesamtgröße <= 4096; Passwortkapazität OAEP geprüft. Fuzz `reviewFuzzRSAKeyParserAndDER` (40 000 Mutationen von SPKI/PKCS#1 plus Rohbytes und gelegentlich `encryptPassword`): kein Trap, kein Hänger. |
| (b) Kein Auth ohne TLS in TLS-Modi, kein Fallback | bestätigt | Fakeserver ohne `CLIENT_SSL` (`nossl`, `plain_fullauth`, `plain_rsa`): `.verifiedTLS` und `.unverifiedTLS` je `mysqlTLSRequired`, 0 Clientbytes (Server-Log `client_bytes: 0`); nur `.plaintext` sendet. Code: der RSA-Zweig hängt an `tlsActive == false`, und das ist in TLS-Modi nicht erreichbar (`tlsActive` wird nach Handshake gesetzt oder die Verbindung bricht ab). Inject-Läufe (6 Zeitpunkte, je 20, abwechselnd verifiziert/unverifiziert): nie akzeptiert. In TLS-Modi geht das Klartextpasswort nur in die TLS-Sitzung (Fakeserver sah es erst nach `tls: established`, TLS 1.3). |
| Auth-Switch-Downgrades | bestätigt | `mysql_clear_password`, `sha256_password`, `client_ed25519`, `mysql_old_password` weiter abgelehnt, auch im Modus `.plaintext` (0 Byte). |
| Deadline | unverändert gut | `idstall` 3,06 s bei 3 s Frist. |
| (c) Schlüsseltausch durch aktiven Angreifer in `.plaintext` | ehrlich benannt | ADR 3a, Risiken und Handoff sagen: Schlüssel kommt über denselben Kanal, ein aktiver Angreifer erhält das Passwort; Nonce ist öffentlich, der Angreifer muss nur Schlüssel tauschen und entschlüsseln. Durch den Fakeserver als Gegenstelle de facto bestätigt (er entschlüsselte das Passwort). Dort ebenfalls: Offline-Ratenangriffe auf den Scramble und erzwungener Wechsel auf `mysql_native_password`. N3 geschlossen. |
| (d) Doku/ADR | konsistent bis auf N5 | Regeln 1/3/4, 3a, Risiken, Abschnitt 6 und Handoff passen zusammen, Altaussagen sind als überholt markiert (N4 geschlossen). |
| (e) Abhängigkeit/Lizenz | in Ordnung | `Security.framework` ist Systembestandteil, `Package.swift` unverändert (`NIOEmbedded` nur Test, schon zuvor), Pins unverändert, `check-dependencies.py` grün. |

Neue Befunde:

**N5 (Niedrig, Doku)** ADR-0007 Abschnitt 6 nennt den unabhängigen Review nur "für den Stand `4faa2e6`".
Tatsächlich sind `026d7d7`, `4faa2e6`, `227b44d` und jetzt `293a949` geprüft (siehe diese Datei); die
Angabe unterschätzt den Prüfumfang und sollte auf `293a949` angehoben werden. Die ADR-Aussage, Versionsmatrix
bleibe Folgearbeit, stimmt weiterhin (nur MariaDB 11.4.4 und MySQL 8.4 geprüft; RSA-Pfad nur gegen MySQL 8.4
und den Fakeserver).

**N6 (Info)** `docs/LIZENZEN.md` erwähnt CryptoKit, aber nicht `Security.framework`/`SecKey` für den neuen
Pfad; der Handoff hält einen Eintrag für unnötig. Für Konsistenz mit der CryptoKit-Zeile ein Satz ratsam,
rechtlich kein Hindernis.

Hinweis: Die Sicherheitsentscheidung des Nutzers (keine Sperre, ungeschönte Folgen) ist umgesetzt wie
beschrieben; es gibt keinen Pfad, der Modus stillschweigend abschwächt.
