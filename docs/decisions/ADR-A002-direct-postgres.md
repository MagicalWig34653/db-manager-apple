# ADR-A002: Direkter nativer PostgreSQL-Pfad

Status: **Akzeptiert für den begrenzten A2-Entwicklungsstand** nach unabhängigem
Review, geschlossenem QA-A2-01 und erfolgreicher exakter Apple-CI an `b72e62c`.
Die konkrete unveröffentlichte NIOssl-Revision samt Original-Lizenzprovenienz ist
ausdrücklich akzeptiert; ihr fehlendes Release-Tag bleibt ein Wartungsrisiko.
Keine allgemeine Distributions-, Geräte-, Signing- oder OS-UI-Freigabe.
Datum: 20.10.2026. [A1](ADR-A001-native-sqlite.md) bleibt vollständig verfügbar.

## Vertrag und Umsetzung

Die SwiftUI-App wählt lokale SQLite-Datei oder direkte PostgreSQL-Verbindung ohne
Go-Server. Katalog und Einzelstatement verwenden dieselben getaggten Ergebnismodelle.
PostgreSQL-Objekte tragen zusätzlich ihr Schema; Navigation quotet beide Identifier.
Keine HTTP-Spezifikation wird implementiert oder als Treibervertrag kopiert.
Neue Zellarten `decimal`, `boolean`, `timestamp` ergänzen die bestehenden Arten.

Ein Actor hält flüchtige Einstellungen und erlaubt eine Operation gleichzeitig je
Arbeitsplatz. Jede Operation öffnet ihre eigene physische Verbindung und schließt
sie vollständig; kein Pool und keine SQL-Session über Requests hinweg. „Verbinden“
prüft Katalogzugriff, bewahrt danach nur Einstellungen im Arbeitsspeicher. Keine
persistente Verbindung, Credentialdatei, Historie, Keychain, Tresor oder Cloudfunktion.
Das Passwortfeld leert sich nach Übernahme; Schließen/Quellenwechsel verwirft die
Adaptereinstellungen. Swift-Stringkopien/RAM/Swap lassen sich damit nicht nachweisbar
sicher löschen. Fehlgeschlagener Wechsel aktiviert keine alten Objekte/Ergebnisse.

## TLS und Abhängigkeitsentscheidung

PostgresNIO **1.33.1**, Commit `39ce38a93408937bcd27f521f3cdf88266136b80`, mit
modernem `PostgresConnection.connect(configuration:id:logger:)` und AsyncSequence.
TLS ausschließlich `.require`, mindestens TLS1.2 und `.fullVerification` mit dem
gewählten Host als Zertifikatsidentität. Darwin-Standardvertrauen oder ausdrücklich
gewählte CA-PEM-Datei (höchstens 1 MiB, ersetzt für diese Verbindung die Wurzeln).
Keine `.prefer`-/`.disable`-/Trust-all-Einstellung; keine Änderung am Systemtruststore.
Der treibereigene Logger ist eine lokale No-op-Instanz. Rohe Treiber-/Serverfehler,
SQL und Credentials verlassen den Adapter nicht als Fehlermeldung oder Log.

Die letzte NIOssl-Releaseversion 2.37.5 referenziert BoringSSL `817ab07...` mit
ursprünglichem OpenSSL-/SSLeay-/ISC-/MIT-Lizenzmix. RootNOTICE allein erlaubt keine
pauschale Apache-Aussage. Unter AGPL-3.0-only wird dieser Stand hier nicht freigegeben.
Statt einer Lizenz-Ausnahme wird der **offizielle unveränderliche, noch nicht als
Release getaggte** NIOssl-Commit `15e0b9e495786807272dd4891fa4bac76aa43034` verwendet.
Seine `Package.swift` und `Sources/CNIOBoringSSL/hash.txt` binden BoringSSL
`8eb25be6fa18d475291122887a7bccd3762ff236`. Dessen konkrete Original-LICENSE ist
Apache-2.0; tatsächliche vendorte Quellheader, etwa `ssl/ssl_lib.cc`, nennen ebenfalls
Apache-2.0 und behalten die OpenSSL-Autoren-Copyrights. Ein Scan der neuen Sources
fand keine alten SSLeay-/Advertising-/GPL-Verbotstexte. Der alte NIOssl-RootNOTICE
bleibt als Original erhalten; sein historischer externer Link ersetzt die konkreten
neuen Belege nicht. **Diese Revisionsentscheidung und Lizenzbewertung muss QA
explizit mitprüfen.** Kein allgemeines juristisches oder Lieferkettenurteil.

SwiftCrypto4.5.2 enthält separat BoringSSL `0226f30467f540a3f62ef48d453f93927da199b6`,
ebenfalls mit konkretem Apache-2.0-Originaltext inventarisiert. Alle 13 SwiftPM-
Abhängigkeiten sind in beiden Lockfiles identisch gepinnt. `swift-collections1.2.1`
hält den Graphen auf der stabilen Swift6.2-Toolchain baubar; keine bewegliche Branchbindung.
Vollständige Originalnotices, BoringSSL-Herkunft und externe Original-LICENSE-Dateien
mit SHA-256 liegen in `Sources/DBManagerCore/Resources/ThirdParty`, werden als
SwiftPM-Ressourcen ins App-Bundle aufgenommen und sind über „Lizenzen und Hinweise“
lesbar. [Inventar](../LIZENZEN.md), `scripts/check-dependencies.py`.

## Lesemodus und Änderungen

Standardmäßig `BEGIN READ ONLY`, danach transaktionslokales `statement_timeout` und
ein echtes SELECT zur eigenen Sessionidentität, **vor** der Benutzeranweisung.
Damit kann nachfolgendes `SET TRANSACTION READ WRITE` die Charakteristik nicht mehr
umschalten. Der DB-Server erzwingt diese lokale Transaktionsregel, kein SQL-Präfixfilter.
Mutierende CTEs und schreibende Funktionen sind in den echten Proben gesperrt.
Extended Query Parse akzeptiert höchstens eine Anweisung und weist Batches vor
deren erster Ausführung ab; Strings/Kommentare mit Semikolon bleiben echte SQL-Syntax.

Bewusste Schreibfreigabe verwendet `BEGIN READ WRITE`; nach vollständigem Ergebnis
folgt COMMIT. Trunkierung/Fehler/Abbruch beendet die Verbindung; kein COMMITversprechen
für abgeschnittene RETURNING-Ergebnisse. Transaktionskontrolle, VACUUM/CREATE DATABASE
und andere nicht im Transaktionsblock erlaubte Befehle sind kein zugesicherter Umfang.
Keine fachliche Rollbackgarantie bei Abbruch/Commitfehler, kein transaktionaler
Workspace über mehrere Ausführungen. READ ONLY ist keine vollständige Sandbox:
DB-Funktionen, Remotezugriffe/Extensions, Ressourcenverbrauch und externe Effekte
sowie erlaubte DB-Sessionparameter bleiben vom Server und seinen Rechten abhängig.

## Grenzen und Abbruch

SQL höchstens 1 MiB, 1–10000 Zeilen, 1 MiB Rohzelle, 8 MiB tatsächlich JSON-encodierte
Ergebnisvergleichsgröße, maximal 1024 Spalten, mehr als 0 bis maximal 60 s validiertes Zeitlimit (UI10 s).
AsyncSequence wird zeilenweise verarbeitet; kein `collect()`. Ein Lookahead erkennt
Zeilentrunkierung und zählt nicht zum Ausgabebudget. Ein Größenfehler liefert kein
Teilergebnis. Netzwerktreiber können vor Anwendungsprüfung einen ganzen Frame/
Puffer allokieren; keine harte Gesamtprozess-RAM-/DoS-/Echtzeitgarantie.

Echte Probe zeigte: Socketclose allein beendet `pg_sleep` serverseitig nicht sofort.
PostgresNIO1.33.1 bietet für diesen Pfad keinen öffentlichen geeigneten CancelRequest.
Deshalb separate **ebenfalls verifizierte TLS-/Authentifizierungsverbindung** für
`pg_cancel_backend`, gebunden an eigene PID, Backendstart, Datenbank, Benutzer und
zufälliges operationseigenes `application_name`. Werte werden als Parameter gebunden;
keine frei übernommene PID und keine erweiterten Rechte angefordert. Danach physisch
schließen; Queryworker und zusätzliche Verbindung werden vor Abschluss abgewartet.
Der Abbruchkanal hat 2 s Connect-/Handshakegrenze und zusätzlich 2 s Querygrenze;
er kann die normale Deadline entsprechend verlängern. Das lokale statement_timeout
ist ein zusätzlicher begrenzter Rückfall, kein universell nicht umgehbarer DoS-Schutz.

Fehlen die Identitätsanker, verweigert der Server Cancellation, oder ist deren
Bestätigung unklar, meldet die App **serverseitigen Abbruch nicht bestätigt**.
SQL kann Sessionparameter verändern; eine veränderte Markierung führt bewusst zu
diesem Ergebnis und nicht zum Signalisieren einer unklaren Session. Keine fremde
Verbindung wird beendet. Ein bestätigtes Signal ist noch keine Rollbackzusage;
Tests prüfen zusätzlich `pg_stat_activity` auf tatsächliche anschließende Freigabe.

## Wertdarstellung und Plattformgrenzen

Numeric wird direkt aus der begrenzten Base10000-Wiredarstellung in einen exakten
String einschließlich Scale umgewandelt; kein Foundation.Decimal/Double mit
Präzisionsverlust. NaN/±infinity bleiben ausdrücklich benannte Decimalwerte.
Int64 bleibt Dezimalstring, NULL/Leertext/Leerblob/Binärbytes getrennt, Bool true/false.
Zeitstempel verwenden sechs exakt ganzzahlig erhaltene Mikrosekundenstellen;
timestamptz wird UTC mit Z, timestamp ohne Zeitzonenbehauptung, date als Datum.
Die Datumsdarstellung berechnet den proleptisch-gregorianischen Kalender allein
mit begrenzten Int64-Operationen aus PostgreSQL-Tagen bzw. Mikrosekunden seit
2000-01-01. Ganzzahlige Schaltjahreszählung und eine begrenzte binäre Jahressuche
ersetzen Foundation-Kalender und Float-Konversion. Negative Tagesreste werden
abwärts gerundet; sechs Mikrosekundenstellen bleiben exakt. Astronomisches Jahr
0 wird als `0001 ... BC` ausgegeben, niemals als dasselbe Datum wie 1 AD. BC erhält
den ausdrücklichen Suffix ` BC` nach Datum bzw. Zeit einschließlich optionalem Z;
AD hat keinen Era-Suffix. Jahre haben mindestens vier Stellen, größere Jahre
werden vollständig ausgegeben. Dies ist bei BC/erweiterten Jahren eine explizite
PostgreSQL-Wertdarstellung, kein behaupteter allgemeiner ISO8601-Parservertrag.
±infinity bleiben ausdrücklich benannt. Auch Int32-/Int64-Wirerandwerte werden
ohne Überlauf behandelt; das erweitert nicht den gültigen Wertebereich des Servers.
Unbekannte Typen/Arrays/Intervalle bleiben Binärbytes samt OID-Metadaten;
kein ungeprüftes Deuten binärer Extensiontypen als Text.

macOS14/iPadOS17 bleiben Deploymentziele. Entwicklung benötigt nun Swift6.2/Xcode26.3
oder neuer; lokaler tatsächlicher Stand Swift6.4/Xcode27.1. Geräte, signierte Sandbox,
Distribution und interaktive OS-UI bleiben getrennte Gates. Die generierte Info.plist
enthält eine deutsche `NSLocalNetworkUsageDescription` für bewusst gewählte LAN-
Ziele. Das ist eine Zweckdeklaration, keine erteilte OS-Berechtigung oder erfolgreich
geprüfter Systemdialog. Native MySQL/MariaDB-
Adapter, SSH, HTTP-Backend, Tresor, iCloud und Teams gehören nicht zu A2.

## Konkrete Primärquellen (Abruf 20.10.2026)

- [PostgresNIO1.33.1, moderner Connection-Pfad](https://github.com/vapor/postgres-nio/blob/39ce38a93408937bcd27f521f3cdf88266136b80/Sources/PostgresNIO/Connection/PostgresConnection.swift)
- [NIOssl fester Commit, BoringSSL-Herkunft](https://github.com/apple/swift-nio-ssl/blob/15e0b9e495786807272dd4891fa4bac76aa43034/Package.swift)
- [Tatsächlich vendorter ssl_lib.cc-Lizenzheader](https://github.com/apple/swift-nio-ssl/blob/15e0b9e495786807272dd4891fa4bac76aa43034/Sources/CNIOBoringSSL/ssl/ssl_lib.cc)
- [Neue BoringSSL-Original-LICENSE](https://raw.githubusercontent.com/google/boringssl/8eb25be6fa18d475291122887a7bccd3762ff236/LICENSE)
- [Zum Vergleich: alter BoringSSL-Lizenzmix](https://raw.githubusercontent.com/google/boringssl/817ab07ebb53da35afea409ab9328f578492832d/LICENSE)
- [SwiftCrypto-BoringSSL-Original-LICENSE](https://raw.githubusercontent.com/google/boringssl/0226f30467f540a3f62ef48d453f93927da199b6/LICENSE)
- [PostgreSQL: Transaktionslesemodus](https://www.postgresql.org/docs/18/sql-set-transaction.html)
- [PostgreSQL: Extended Query und Abbruch](https://www.postgresql.org/docs/18/protocol-flow.html)
- [PostgreSQL: Signalisierungsrechte](https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL)
- [Apple: lokale Netzwerkprivatsphäre und Zweckbeschreibung](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [PostgreSQL: Numeric-Wireformat, numeric_send/recv](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/utils/adt/numeric.c)
- [PostgreSQL: proleptischer Kalender und Zeitwertebereiche](https://www.postgresql.org/docs/18/datatype-datetime.html)
- [US Naval Observatory: gregorianische Schaltjahresregeln](https://aa.usno.navy.mil/faq/calendars)
