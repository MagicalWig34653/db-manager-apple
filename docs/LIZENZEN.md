# Lizenzen

Eigener Projektcode: `AGPL-3.0-only`, vollständiger Text in [LICENSE](../LICENSE).
Keine zusätzliche Lizenz-Ausnahme. Drittanbieter behalten ihre Lizenzen.
Vor Aufnahme weiterer Abhängigkeiten: Name, Version, Herkunft,
Lizenz, Verteilungsform, notwendige Hinweise und Kompatibilitätsprüfung erfassen.
Apple-Vertriebsweg und konkrete Treiberlizenzen sind vor Release gesondert zu bewerten.

## Native Grundlage A1

Keine externen Swift-Paketabhängigkeiten und kein vendorter Drittcode. System-
`libsqlite3` wird aus dem Apple-SDK dynamisch eingebunden. SQLite steht grundsätzlich
in der [Public Domain](https://www.sqlite.org/copyright.html); die Apple-System-
Distribution und SDKs unterliegen zusätzlich den jeweiligen Apple-Bedingungen.
`CSQLite/shim.h` und das Modulemap sind eigener minimaler Bindungscode.

Swift/SwiftUI/Foundation sowie Xcode/Swift Testing werden als vorhandene Apple-/
Swift-Toolchain genutzt; keine Kopie von Apple-Frameworks im Repository.
[Swift](https://www.swift.org/legal/license-overview/) verwendet Apache-2.0 mit
Runtime Library Exception, Apple-SDK-/Vertriebsbedingungen gelten gesondert.
Tatsächlich geprüft mit Swift 6.4/Xcode 27.1; SystemSQLite-Version hängt vom
ausführenden OS ab, keine gebündelte fixe SQLite-Version zugesagt. Signierter
Vertrieb, App-Store-/AGPL-Kompatibilität und vollständige Releasehinweise bleiben
vor Veröffentlichung einer App gesondert zu prüfen.

## Direkter PostgreSQL-Pfad A2

PostgresNIO wird eingebunden, kein Treiberquellcode eigenmächtig umgeschrieben.
Eigener Code bleibt AGPL-3.0-only ohne zusätzliche Ausnahme. Die tatsächlichen
13 Abhängigkeiten stehen mit Version/Commit/URL und Originalnotice-Hashes im
[maschinenlesbaren Inventar](../Sources/DBManagerCore/Resources/ThirdParty/inventory.json).
Beide Lockfiles binden denselben Graphen; `scripts/check-dependencies.py` prüft
diese Gleichheit und sämtliche aufgenommenen Originaltexte.

| Paket | Fester Stand | Lizenz |
| --- | --- | --- |
| `postgres-nio` | `1.33.1` | MIT |
| `swift-asn1` | `1.7.3` | Apache-2.0 (Originalnotices beachten) |
| `swift-async-algorithms` | `1.1.3` | Apache-2.0 mit Swift Runtime Library Exception |
| `swift-atomics` | `1.3.1` | Apache-2.0 mit Swift Runtime Library Exception |
| `swift-collections` | `1.2.1` | Apache-2.0 mit Swift Runtime Library Exception |
| `swift-crypto` | `4.5.2` | Apache-2.0 (Originalnotices beachten) |
| `swift-log` | `1.16.1` | Apache-2.0 (Originalnotices beachten) |
| `swift-metrics` | `2.12.0` | Apache-2.0 (Originalnotices beachten) |
| `swift-nio` | `2.104.0` | Apache-2.0 (Originalnotices beachten) |
| `swift-nio-ssl` | `Revision 15e0b9e495786807272dd4891fa4bac76aa43034` | Apache-2.0 (Originalnotices beachten) |
| `swift-nio-transport-services` | `1.28.0` | Apache-2.0 (Originalnotices beachten) |
| `swift-service-lifecycle` | `2.13.0` | Apache-2.0 (Originalnotices beachten) |
| `swift-system` | `1.8.1` | Apache-2.0 mit Swift Runtime Library Exception |

NIOssl enthält eine eigene vendorte BoringSSL-Kopie; SwiftCrypto eine weitere.
Diese Anteile sind nicht aus einem pauschalen Rootlizenz-Eintrag abgeleitet:

- NIOssl-Revision `15e0b9e495786807272dd4891fa4bac76aa43034` bindet BoringSSL
  `8eb25be6fa18d475291122887a7bccd3762ff236`.
- SwiftCrypto4.5.2 bindet BoringSSL `0226f30467f540a3f62ef48d453f93927da199b6`.
- Jeweilige `hash.txt`, genaue externe Original-LICENSE und SHA stehen im Inventar
  und im zugehörigen Ressourcenunterordner `boringssl`. Beide konkreten Originaltexte
  nennen Apache-2.0; Quellen/Quellheader und Abgrenzung zum älteren NIOssl-Release
  stehen in [ADR-A002](decisions/ADR-A002-direct-postgres.md).
- Die NIOssl-RootNOTICE mit ihrem historischen Verweis bleibt unverändert erhalten.
  Ein nicht existierendes `Sources/CNIOBoringSSL/LICENSE` wird nicht als Beleg ausgegeben.
- Der letzte untersuchte Release-Tag 2.37.5 hatte einen anderen BoringSSL-Stand mit
  älterem OpenSSL-/SSLeay-/ISC-/MIT-Mix. Er wurde hier nicht mit AGPL-Ausnahme eingebunden.

Der feste offizielle **Unreleased-Revisionspin** ist eine bewusste Abweichung von
einem Release-Tag und bleibt Gegenstand der unabhängigen QA. Keine allgemeine
Rechtsfreigabe. Der neue Code und die neue Abhängigkeitsentscheidung werden vor
Integration getrennt geprüft. Updates müssen Lockfiles, Inventar, Originaltexte,
BoringSSL-Provenienz, TLS-Negativtests und native Builds zusammen aktualisieren.

Die vollständigen Ressourcen werden ins SwiftPM-Ressourcenbundle und damit ins
App-Bundle kopiert. „Lizenzen und Hinweise“ zeigt eigene AGPL-Lizenz, sämtliche
Originaltexte und Herkunft an. Ein Runtime-Test prüft das tatsächliche Laden;
Buildprüfung kontrolliert zusätzlich die im erzeugten Mac-/iPad-App-Bundle
enthaltenen Dateien. Für vertriebene Binaries sind außerdem entsprechender
Quellzugang, signierter Vertriebsweg und vollständige Releaseunterlagen nötig.

## Nativer MySQL-/MariaDB-Pfad A4 (Vorschlag)

Eigener Protokollcode (AGPL-3.0-only) in `Sources/DBManagerCore/MySQL*.swift`, keine neue
Paketabhängigkeit und kein vendorter Fremdcode. `Package.swift` bindet lediglich zwei weitere
Produkte des bereits gepinnten und inventarisierten `swift-nio` (`NIOPosix`, `NIOTLS`) in
`DBManagerCore` ein; `Package.resolved` und
[inventory.json](../Sources/DBManagerCore/Resources/ThirdParty/inventory.json) bleiben
unverändert (`scripts/check-dependencies.py` bestätigt das). Anmelde-Hashes (SHA-1/SHA-256)
kommen aus Apples CryptoKit (Systemframework, Apple-Bedingungen), nicht aus einer
Drittbibliothek. MySQLNIO, MariaDB Connector/C und libmysqlclient werden nicht eingebunden;
Begründung in [ADR-0007](https://github.com/MagicalWig34653/db-manager/blob/main/docs/decisions/ADR-0007-native-mysql-adapter.md)
(Root-Repository, Status Vorschlag) und [A4](handoffs/A4-mysql.md). Die Testfixtures
verwenden die offiziellen Docker-Images `mariadb:11.4.4` und `mysql:8.4` nur als
wegwerfbare lokale Container; sie werden nicht verteilt.
