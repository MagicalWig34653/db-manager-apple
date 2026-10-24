# A4: Nativer MySQL-/MariaDB-Adapter (erster begrenzter Schritt)

Stand: 23.10.2026. Worktree `.worktrees/mysql-adapter`, Branch `feat/mysql-adapter`,
Basis `84c7504`. Implementierer; zur unabhängigen Prüfung. Keine Integration nach `main`,
keine eigene Freigabe. `STATUS.md`/`ARBEITSPLAN.md` unverändert (Lead). UI
(`Sources/DBManagerApp`, `DBManager.xcodeproj`) nicht angefasst: der Adapter ist **nicht**
in die App eingebunden.

## Entscheidung (Vorschlag)

[ADR-0007](https://github.com/MagicalWig34653/db-manager/blob/main/docs/decisions/ADR-0007-native-mysql-adapter.md)
im Root-Repo (Status **Vorschlag**, Branch `docs/adr-0007-native-mysql`). Kurzfassung:

- Der Downgrade in MySQLNIO 1.9.2 ist fehlende Pflicht-TLS: Der Handshake startet TLS nur,
  wenn Client-Konfiguration **und** Server-`CLIENT_SSL` vorliegen, sonst Klartextanmeldung.
  Das Greeting ist unauthentifiziert, ein Angreifer kann `CLIENT_SSL` entfernen.
- Gewählt: Option (a), eigener minimaler Textprotokoll-Client auf NIO + NIOSSL. (b) Patch
  verworfen (tiefer Zustandsautomat, Fork-Pflege, Backpressure/Abbruch bleiben offen),
  (c) keine gleichwertige MIT/Apache-Swift-Bibliothek; C-Connectoren (GPL/LGPL, eigenes
  OpenSSL) für iOS/AGPL nicht ohne Rechtsprüfung.
- Keine neue Paketabhängigkeit (NIOPosix/NIOTLS aus gepinntem swift-nio, Hashes via CryptoKit).

## Umgesetzt

- `MySQLSettings`/`MySQLDatabase` (Actor, API wie `PostgresDatabase`: `open`, `objects`,
  `execute`, `close`, `selectSQL`). `MySQLConnection` (NIO-Kanal, Backpressure),
  `MySQLWire` (Greeting, Pakete, Auth, Spalten, Werte).
- TLS: standardmäßig Pflicht, TLS ≥ 1.2, `.fullVerification`, Host als Identität, optionale CA
  nur für die Verbindung. Ablauf: Greeting, fehlt `CLIENT_SSL` dann `mysqlTLSRequired` ohne
  Anmeldebytes, SSLRequest, TLS-Handshake, erst dann Anmeldung. Klartext nur mit
  `.plaintextLoopbackDevelopmentOnly` (nur Loopback-Hosts, nicht mit CA kombinierbar). **Überholt durch die Nutzerentscheidung unten.**
- Auth: `mysql_native_password`, `caching_sha2_password` (Fast-Auth, Full-Auth nur über TLS,
  Auth-Switch). Andere Plugins werden abgelehnt.
- SELECT/Einzelstatement: exakt DECIMAL, BIGINT UNSIGNED, Mikrosekunden, BLOB (Base64),
  NULL, leere Werte, UTF-8 inkl. Emoji; Nulldaten und TIME bleiben Text. Zeilen-/Zell-/
  Ergebnisbytes, Paketgröße vor Pufferung, Sequenzprüfung, ≤ 1024 Spalten.
- Deadline/Cancel: Socket schließen plus `KILL QUERY` über zweite verifizierte Verbindung,
  `canceled`/`cancellationUnconfirmed`; serverseitig `max_execution_time`/`max_statement_time`
  als Rückfall. Lesemodus per `START TRANSACTION READ ONLY`; Schreiben nur mit Freigabe.
- Katalog: Datenbanken als `schema`, Tabellen/Views als Objekte (System-Schemas ausgeblendet).
  Einen Spaltenkatalog verlangt die vorhandene Core-Schnittstelle nicht (`DatabaseObject`);
  Spalten kommen mit dem Ergebnis.
- Fehler: feste deutsche Texte plus numerischer Serverfehlercode, kein SQL/Pfad/Secret.

## Tatsächlicher Prüfstand (23.10.2026, macOS arm64, Xcode/Swift 6.4)

- `python3 scripts/test-mysql.py`: eigene Wegwerf-Container (`mariadb:11.4.4` mit TLS,
  mit falschem Zertifikat, ohne TLS via `--skip-ssl`; `mysql:8.4` mit TLS), selbst erzeugte
  Test-CA, danach `docker rm -f -v`. Alle Tests bestanden (34 Meldungen "passed" im Gesamtlauf
  inkl. SQLite/Postgres-Bestand; Postgres-Livetests dort ohne Fixture übersprungen).
- Unit (ohne Server): TLS-Standard, Loopback-Regel, Auth-Vektoren (unabhängig mit Python
  hashlib berechnet), Längenkodierung, Paket-/Sequenz-/Limitprüfung, Greeting-Kürzungen,
  Werte-Exaktheit.
- Live: Präzision/Katalog/Lesemodus gegen MariaDB (native_password) **und** MySQL 8.4
  (caching_sha2_password); Negativtests: Server-CA unbekannt, unverwandte CA, IP statt Hostname,
  Zertifikat für anderen Host, Server **ohne TLS** (`mysqlTLSRequired`, kein Downgrade),
  falsches Passwort; Klartextoption nur Loopback und nur auf ausdrückliche Anforderung;
  Zeilenlimit, Zell-/Ergebnisgrenze, Deadline, Task-Abbruch inkl. serverseitigem Verschwinden
  der Abfrage, parallele fremde Sitzung bleibt intakt, Fehlertext ohne SQL/Namen/Passwort.
- Beobachtung: neuere MariaDB-/MySQL-Images erzeugen selbst ein Zertifikat; "ohne TLS" erfordert
  `--skip-ssl`. Ohne diese Option scheiterte der Test zunächst korrekt an der Verifikation.
- Abbruch-/Cancelprobe nur gegen MariaDB, nicht gegen MySQL 8.4.

Weitere Prüfungen: `check-dependencies.py` (13 Pins, auch gegen Checkouts), `swift test
--force-resolved-versions` (ohne Fixtures: 29+5 Tests bestanden, Livetests übersprungen),
`check-calendar-vectors.py`, `xcodebuild` macOS und iOS Simulator (`generic/platform`, ohne
Signierung) erfolgreich, `check-docs.py` in beiden Repos ohne Fehler.
**`scripts/check-apple.sh` nicht vollständig grün:** der erste Schritt `check-icon.sh`
scheitert hier mit einem actool-Fehler auf einem fremden Pfad (`timetrack-apple-wt/...`) beim
Icon-Export; Umgebungsproblem des lokalen Hosts, nicht durch A4 verändert, aber nicht
aufgeklärt. Die übrigen Schritte des Skripts wurden einzeln ausgeführt (siehe oben); das
Skript selbst lief daher nie komplett durch.

## Offene Punkte und Grenzen (ehrlich)

- Nicht in die UI eingebunden; Darstellung/Persistenz der Klartext-Entwicklungsoption offen.
- Textprotokoll nur; keine Prepared Statements, Clientzertifikate, Unix-Sockets, Kompression,
  Multi-Statement, Multi-Resultsets, `LOCAL INFILE`. Andere Auth-Plugins werden abgelehnt.
- `caching_sha2_password` ohne TLS bewusst nicht unterstützt.
- Versionsmatrix klein: MariaDB 11.4.4 und MySQL 8.4 (Docker-Image-Stand lokal). Keine 10.x/
  11.8/12-, MySQL-8.0- oder Percona-Prüfung. Abbruchprobe nur MariaDB. Kein mTLS-Test, kein
  Test mit abgelaufenem Zertifikat und kein Test, der ein aktiv manipuliertes Greeting
  (CLIENT_SSL entfernt) mit einem eigenen Fake-Server nachstellt; der Pfad ist derselbe wie
  bei dem Server `--skip-ssl`, aber nicht separat bewiesen.
- Eigener Protokollparser ohne Fuzzing/externes Audit; Reviewer sollte `MySQLConnection.handshake`
  (TLS vor Auth, keine Ausnahme-Pfade) und `MySQLPacketAssembler` gezielt prüfen.
- Zeitwerte: TIMESTAMP wird als UTC (`Z`) gedeutet, weil die Sitzung auf `+00:00` steht;
  DATETIME ohne Zone. `YEAR`/`BIT` und exotische Typen (GEOMETRY, JSON als Text) nur
  grob typisiert; Zeichensatz außerhalb UTF-8 für Textspalten wird nicht umkodiert
  (nicht-UTF-8-Bytes führen zu `invalidText`).
- Lesemodus ist keine vollständige Sandbox (Implicit-Commit-DDL bei schreibberechtigten
  Konten, Serverfunktionen); `SET`/`COMMIT` als einzelne Anweisung bleibt möglich, wirkt aber
  nur auf die Wegwerf-Verbindung.
- CryptoKit-Abhängigkeit ist Apple-only. `KILL QUERY` braucht ein Konto, das eigene Threads
  beenden darf (Standard), und eine zweite Verbindung (zusätzliche Latenz bis 2 s).
- `test-mysql.py` startet nur eigene, per Label `dbmanager.task=A4` markierte Container und
  löscht sie am Ende (nach dem letzten Lauf keine A4-Container vorhanden). Docker-Images
  verbleiben im lokalen Cache.

## Review-Auflagen (Nachbesserung nach A4-Review (`docs/handoffs/A4-review.md` auf Branch `review/a4-mysql`))

- F1: Vor und nach dem TLS-Aufbau muss die Eingangswarteschlange leer sein
  (`requireNoQueuedData`, im Eventloop unmittelbar vor dem Einbau des TLS-Handlers); sonst
  `mysqlProtocolError`. Test mit EmbeddedChannel. Ein Bytes-Eintreffen nach dem Einbau landet
  im TLS-Handler und scheitert dort.
- F2: `KILL QUERY` nutzt `SELECT CONNECTION_ID()` nach der Anmeldung statt der Greeting-ID.
- F3: `MySQLSettings` und `MySQLConnectionConfig` geben in `description`, `String(reflecting:)`
  und `dump` nichts preis. Test.
- F4: Wechsel des Auth-Plugins gegenüber dem Greeting (z. B. caching_sha2 auf native) nur bei
  aktivem verifiziertem TLS, Antwort bleibt ein Scramble. Bewusste Restschwächung: Ein
  kompromittierter, aber zertifikatsgültiger Server kann ein schwächeres Scramble verlangen.
  Kein Einzeltest über Fakeserver, nur Code und Live-Anmeldungen.
- F5: Eigene Limit-Abbrüche (`resultTooLarge`, `invalidText`) behalten ihre Ursache, auch wenn
  das nachfolgende `KILL` nicht bestätigt wird (`MySQLDatabase.failure`, Test). Nutzerabbruch
  bleibt `cancellationUnconfirmed`. Die Wartezeit des Kill-Kanals (bis 2 s zusätzlich) bleibt.
- F6: Abbruchprobe läuft jetzt gegen MariaDB und MySQL 8.4. ERR-Pakete statt Spaltendefinition
  oder EOF werden als Serverfehler gemeldet. Der Katalog ist auf 10.000 Objekte begrenzt;
  darüber `resultTooLarge` (kein Teilkatalog), Paginierung offen.
- Angriffsharness aus dem Review (`scripts/review-a4-fakeserver.py`,
  `Tests/DBManagerCoreTests/MySQLReviewAttackTests.swift`) unverändert übernommen. Die Tests
  sind über `DBM_A4R_DIR` gesteuert und laufen ohne Variable nur als reine Parser-Tests.
  Aufruf wie im Review beschrieben; der Fakeserver-Lauf wurde nach den Fixes nicht wiederholt.
- Prüfstand nach den Fixes: `scripts/test-mysql.py` bestanden (Livesuite einschließlich
  Abbruchprobe gegen beide Server), dazu die Läufe unten im Abschnitt zuvor erneut.

## Nutzerentscheidung: TLS nicht erzwungen, aber ausdrücklich gewählt (24.10.2026)

Der Nutzer hat entschieden, dass der native Client TLS nicht erzwingen muss. Umgesetzt als
ausdrückliche Einstellung pro Verbindung (`MySQLSettings.transportSecurity`), nie als stiller
Fallback. Die Loopback-Entwicklungsoption ist ersetzt.

| Modus | Warnstufe (`.warning`) | Verhalten |
| --- | --- | --- |
| `.verifiedTLS` (Standard) | `.none` | TLS >= 1.2, Zertifikat und Hostname geprüft, optionale CA |
| `.unverifiedTLS` | `.serverIdentityUnverified` | TLS ohne Zertifikat- und Hostnamenprüfung; Server kann von einem aktiven Angreifer imitiert werden |
| `.plaintext` | `.noEncryption` | kein TLS, auch für Nicht-Loopback-Hosts; alles mitlesbar und veränderbar |

- Fehlt `CLIENT_SSL` beim Server und ein TLS-Modus ist gewählt, bricht der Client weiter mit
  `mysqlTLSRequired` vor dem ersten Authentifizierungsbyte ab (Test gegen echten Server und
  Fakeserver, auch im Modus `.unverifiedTLS`). Es gibt keinen automatischen Wechsel.
- Eine CA-Datei zusammen mit `.unverifiedTLS` oder `.plaintext` wird abgelehnt (Widerspruch),
  nicht stillschweigend ignoriert. `MySQLTransportSecurity.allCases`, `.warning`, `.usesTLS` und
  `.verifiesServerIdentity` erlauben der UI eine klare Auswahl und Warnanzeige.
- Passwortschutz ohne TLS: Das Passwort verlässt den Client nur als Scramble
  (`mysql_native_password`, `caching_sha2_password` Fast-Auth, auch per Auth-Switch zwischen diesen
  beiden). `caching_sha2` Full-Auth (Server verlangt das Klartextpasswort) wird ohne TLS mit
  `mysqlUnsupportedAuth` abgelehnt; der RSA-Public-Key-Austausch ist **nicht** umgesetzt (würde
  einen unauthentifizierten Schlüssel vom Server übernehmen, also ohne Server-Identität sinnlos).
  Praktische Folge: Konten mit `caching_sha2_password`, die der Server noch nicht im Cache hat,
  können sich ohne TLS erst nach einer TLS-Anmeldung verbinden. Test mit frischem MySQL-8.4-Konto.
- Folge von `.unverifiedTLS`: Bei Full-Auth wird das Klartextpasswort in einen TLS-Kanal gesendet,
  dessen Gegenstelle nicht geprüft wurde. Ein aktiver Angreifer erhält es. Die Warnstufe
  `.serverIdentityUnverified` muss das der UI deutlich sagen.
- F4 angepasst: Der Auth-Switch auf ein anderes unterstütztes Scramble-Plugin ist in allen Modi
  erlaubt (nie Klartext); nicht unterstützte Plugins bleiben abgelehnt.
- Server-seitiges `max_execution_time`/`max_statement_time` liegt jetzt eine Sekunde über der
  Clientfrist, damit die Clientfrist samt `KILL` deterministisch zuerst greift.

### Nachreview-Befund N1

`SELECT CONNECTION_ID()` läuft jetzt im abbrechbaren Bereich unter der Nutzerfrist. Die Messung
des Reviews (ca. 10,5 s bei 3 s Frist) kam zusätzlich daher, dass `open()` den Katalog mit einer
festen 10-s-Frist las; `open(_:timeout:)` nimmt die Frist jetzt als Parameter. Fakeserver
`idstall`: Rückkehr mit `canceled` nach rund 3,1 s bei 3 s Frist. Der Test ist Teil des
Review-Harness (`DBM_A4R_DIR`), kein deterministischer Unit-Test.

### Prüfstand dieser Änderung

`scripts/test-mysql.py` (Live: alle drei Modi positiv, TLS-Modi gegen Server ohne TLS negativ,
plaintext gegen frisches caching_sha2-Konto negativ), Fakeserver-Harness (Downgrade, Modus
`.unverifiedTLS` ebenfalls ohne Clientbyte abgebrochen, idstall) und weitere Läufe siehe
Abschlussbericht. Nicht getestet: `.unverifiedTLS` gegen ein tatsächlich manipulierendes
Zwischensystem (die Folge ist per Definition ungeschützt), RSA-Austausch (nicht implementiert).

Ergebnis dieser Änderung (24.10.2026): `test-mysql.py` bestanden (38 Tests, keine A4-Container
danach), `swift test` 38 + 5 bestanden, `check-dependencies.py`, `check-docs.py`, `xcodebuild`
macOS und iOS Simulator erfolgreich. Fakeserver-Lauf: `nossl` mit `.verifiedTLS` und
`.unverifiedTLS` je 0 Clientbytes, `plain_fullauth` und `plain_switch_clear` abgelehnt, idstall
`canceled` nach 3,1 s.
