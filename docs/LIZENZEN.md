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
