# C-Export1 / A3 – aufgeschobener Vorschlag

23.10.2026. Nur Planung, keine freigegebene Kanonik oder Implementierung.
Zugunsten GitHub Pages und dringender TestFlightvorbereitung zurückgestellt.

Grundlage: unabhängig akzeptierte Web-F6-Quelle
1a8adfa4174aafe1850b843909af023b4357ebaa, src/lib/export.ts und HandoffF6.
Native QueryResult hat geordnete columns(name,database_type), acht Zelltags,
rows, truncated, rowsAffected und durationMS. Export nimmt nur explizit erlaubte
Felder eines bereits geladenen erfolgreichen Snapshots, keine DBneuabfrage,
keine Credentials/SQL/Sessiondaten. Native Quelle zunächst nur sql_result.

Vorgeschlagenes erstes Paket: eigener Root-Vertragsworktree export-contract,
Besitz ausschließlich contracts/export/result-v1.schema.json, README,
synthetische Fixtures/Quellenhashlock und HandoffC-Export1. Keine vorhandenen
API-/Index-/B4-Dateien oder zentralen Rootdokumente ändern. Envelope exakt F6:
schema_version1, scope sql_result oder table_page(offset,page_size,has_more),
truncated, geordnete columns[{name,type}], rows mit NULL ohne value und allen
anderen Zellwerten als Strings. Breite muss zur Spaltenanzahl passen; endgültige
UTF8-Bytes maximal8MiB. Kein Anspruch bytekanonischer JSONrepräsentation.

Fixtures: doppelte/leere Namen, Int64/Decimal40,20, Floatstrings/-0, BC/AD/Zeit,
NULL/leer/Base64, Unicode/C0, Trunkierung/Seitenumfang. Negative unbekannte Felder,
ungültige Tags/Werte, Zeilenbreiten und Bytegrenze. Herkunft exakt pinnen und
unabhängig abnehmen; Web und Swift prüfen denselben dekodierten semantischen Inhalt.

CSVprofil unverändert F6: UTF8 ohneBOM, Komma/CRLF, Header/NichtNULL immer gequotet,
NULL ungequotetes \N. Roh- und ausdrücklich datenverändernde Apostrophvariante.
C0 außerCR/LF sowieDEL/C1 vor Dateiangebot ablehnen; kein allgemeiner Roundtrip
oder Excel-Sicherheitsclaim. JSON erhält Zeichen unverändert.

Erst nach Vertragsfreigabe A3 in eigenem Appleworktree: enger Exporthelper,
ViewModel-/SwiftUI-fileExporter-Anbindung und Tests. Explizites database_type→type-
Mapping; keine Quittungen ohne Spalten. Quellen-/Sessionwechsel oder neue Fehler
entfernen alten Exportzustand. Tests: gleiche Vektoren, wirkliche finale Bytegrenze,
CSVreject vor Dateianlage, Lifecycle, kein DBaufruf, Mac/iPadBuild. Echter OSdialog
bleibt separat. Keine Umsetzung begonnen, kein neuer Slot angefordert.
