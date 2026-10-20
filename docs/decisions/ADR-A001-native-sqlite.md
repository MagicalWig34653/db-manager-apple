# ADR-A001: Erste native SQLite-Grundlage

Status: als begrenzte Entwicklungsgrundlage nach unabhängiger QA akzeptiert, 20.10.2026.
macOS14/iPadOS17 sind Deployment-Arbeitsziele, keine belegte Altgeräte-/Distributionsfreigabe.

## Kontext

Die Apple-App muss ohne Go-Server Datenbanken bearbeiten können. Die gemeinsame
[Treiberuntersuchung P2a](https://github.com/MagicalWig34653/db-manager/blob/9a6489a/docs/handoffs/P2a.md)
belegt SystemSQLite3-Proben und empfiehlt zunächst macOS 14/iPadOS 17. Sichere
MySQLNIO-Netzwerkfreigabe ist wegen des dort bestätigten TLS-Downgradebefunds offen.
Native PRF-/iCloud-Entscheidungen gehören nicht zu dieser ersten Stufe.

## Entscheidung und tatsächliche Umsetzung

SystemSQLite3 aus dem Apple-SDK, Swift-Actor für die Verbindung und native SwiftUI-
Oberfläche. macOS 14/iPadOS 17 sind begründete erste Arbeitsziele: `@Observable`,
NavigationSplitView und die verwendete SwiftUI-Oberfläche passen zu diesen Zielen;
kein Framework zwingt in diesem Paket zu einem eigenen Backend. Das Deploymentziel
ist im Paket und Xcode-Projekt festgelegt. Builds mit neuem SDK beweisen keine
Altgerätekompatibilität; reale Hardware und Ziel-OS-Laufzeit bleiben Prüfaufgaben.

Nur eine aktive lokale Datei je Fenster, ein Statement je Ausführung. Actor-
Isolation verhindert gleichzeitigen Zugriff auf den Verbindungshandle; alle
SQLite-Arbeit läuft außerhalb des MainActor. Ein per Lock geschütztes Abbruchsignal
erreicht SQLite während synchroner Arbeit über den Progresscallback. Dateisperren
sind zeitlich begrenzt. Zeilen-, Zell-, Ergebnis- und SQL-Längenlimits verhindern
unbeschränkte Ausgabe. Die App ist kein vollständiger Prozess-/Dateisystemsandbox-
Nachweis und bietet keine harte I/O-Latenzgarantie.

Schreibzugriffe benötigen Toggle plus Ausführung. Der SQLite-Authorizer sperrt
mutierende Operationen bereits beim Prepare; `sqlite3_stmt_readonly` ergänzt die
Prüfung. Nur bekannte lesende Metadaten-PRAGMAs werden zugelassen, weil manche
PRAGMAs bereits beim Prepare wirken. `ATTACH`, `DETACH` und Extensionladen bleiben
auch mit Schreibfreigabe gesperrt; `VACUUM` kann deshalb ebenfalls abgewiesen werden.
Keine naive Suche nach SQL-Schlüsselwörtern als Sicherheitsprüfung.

Werte folgen der gemeinsamen Semantik: NULL ohne value, leere Werte mit leerem
String, 64-Bit-Integer als Dezimalstring, BLOB als Base64. SQLite kann NUMERIC-
Affinität als Float speichern; solche vorhandenen Rundungsverluste werden nicht
als erhaltene Dezimalpräzision ausgegeben. Datums-/Boolwerte bleiben entsprechend
SQLite-Speichertyp Text/Integer; keine erfundenen Typzusagen. Doppelte Spaltennamen
und ihre Position bleiben erhalten. Diese lokale Kernbibliothek implementiert
keine HTTP-API und hat keine Laufzeitabhängigkeit vom Backendvertrag.

## Alternativen und Folgen

GRDB könnte später Migrationen, Beobachtung und eine umfangreichere Zugriffsschicht
vereinfachen, wäre aber eine neue zu prüfende Abhängigkeit. Ein Webview-/Backendclient
allein erfüllt den eigenständigen lokalen Betrieb nicht. Ein großer ungeprüfter
Treiberverbund würde TLS-/Geräteprobleme in diese klar begrenzte Stufe tragen.

Systembibliotheken behalten ihre Lizenzen. Kein Netzwerkadapter, Credentialtresor,
CloudKit, Passkey, Verbindungsbookmark oder produktiver SQL-Verlauf. Lokale
SQLite-Dateien sind bewusst vom Benutzer angelegte/geöffnete Nutzdaten und werden
nicht zusätzlich durch einen eigenen Tresor verschlüsselt. Dokumentierte Grenzen
und tatsächliche Prüfungen stehen im [A1-Handoff](../handoffs/A1.md).

## Primärquellen

Recherche 20.10.2026, Dokumentation ist kein eigener Plattformtest:

- [SQLite Progresscallback](https://www.sqlite.org/c3ref/progress_handler.html)
- [SQLite Ergebnisspalten](https://www.sqlite.org/c3ref/column_blob.html)
- [SQLite Authorizer](https://www.sqlite.org/c3ref/set_authorizer.html)
- [SwiftUI Dateiauswahl](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:))
- [Apple: Sandbox-Dateizugriff](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
