# Arbeitsplan

Stand: 23.10.2026. Root koordiniert; Agents implementieren, prüfen, dokumentieren
und übernehmen ausdrücklich delegierte Integrationen. Nutzerverlängerung bis
heute 10:00 Europe/Berlin (=08:00 UTC), oder vorher vollständiger Abschluss.
Apple-STATUS/ARBEITSPLAN sind im Fortsetzungsfenster allein an S2a delegiert;
Hauptrepo-Statuspflege liegt beim dort beauftragten Agent.

| ID | Auftrag | Tatsächlicher Stand und Abnahme |
| --- | --- | --- |
| P0 | Eigenständiges öffentliches Repo, Lizenz und Agent-Einstieg | abgeschlossen |
| A1 | Eigenständiger nativer SQLite-/SwiftUI-Arbeitsplatz | nach QA und CI integriert; zehn Tests, Mac-/Simulatorbuild, Lifecyclefix geschlossen |
| A2 | Direkter PostgreSQL-Pfad ohne Go, SQLite erhalten | Quellen89b2683/abaa3dc/b72e62c nach unabhängigem Review und exakter grüner CI integriert als fdd533e/cd5d886/031b1e8; Kalenderbefund geschlossen, konkreter NIOssl-Pin akzeptiert. Leadintegrationsprüfung bestanden; Main-CI39505094304 auf7e97aae erfolgreich; unabhängiger Review als A2-review dauerhaft gesichert. |
| S2a | Eigenständiger Vault-Core ohne Appverdrahtung | Nach unabhängigem Review ohne Findings als isolierter Core abgenommen; vollständige Historie mit Originalpins übernommen, kombinierte Vault-/A2-Appchecks grün; Main-Vault39903661136/Docs39903661079 bestanden, Apple39903661074 ebenfalls tatsächlich erfolgreich. Keine produktive Persistenzfreigabe |
| A-TF1 | Bundle-ID und TestFlightvorbereitung | eigener Kandidat release/testflight-preparation: de.linolaske.dbmanager explizit registriert, signierte iPad-/Universal-Macarchive und lokale App-Store-Exports bestanden; echtes editierbares Composericon, kein Upload. Review/CI/Betreiberauskünfte offen |
| S2b | Produktiver Anchor und App-/Recoveryablauf | isoliertes Gate G-S2b durchgeführt: SecItemAdd=-34018 bei eigenem ad-hoc-Host ohne Team-ID; keine Itemanlage, CAS/Lock/Unsicherheit ungeprüft. Separater Probebranch4953399; produktiver Anchor und Appsecretpersistenz gesperrt |

S2a-Dateibesitz: nur neues Packages/DBManagerVault samt Tests/Fixtures/Originaltexten/
Locks, eigene Vault-CI/Skripte, neue Sicherheitsdokumente/ADR-A003/HandoffS2a. Keine
App-/Xcode-/Rootpackage-/DBManagerCore-/A2-Produktänderungen. Nur Apple-STATUS und
ARBEITSPLAN sind für das neue Zeitfenster zusätzlich ausdrücklich delegiert. Actor-Session,
verwaltete private Dateiablage, sichere Deskriptoren/flock/CAS/temp0600/fsync/rename,
extern dauerhafte Reservierung jeder Root-AEAD-Nutzung vor Verschlüsselung. Anchor
bindet VaultID/Epoch/Generation/Hash/Lebenszeitverbrauch; Pendingzustände nur über
exakt bekannte alte/neue Hashes auflösen. Fehlender oder zurückrollbarer Anchor
öffnet keine schreibende Produktsession. Kein produktiver InMemory-Fallback; nur
Testtarget darf synthetischen Anchor implementieren.

Explizite Recovery: ein überlebender alter Faktor darf in neuen Tresor mit neuem
Master und neuer Recovery migrieren, beide neuen Faktoren tatsächlich rücklesen,
Original erhalten. Kein Wiederherstellen unbekannter alter Faktoren. Rotation unter
Erhalt beider bisherigen Faktoren kann beide alten Nachweise erfordern. Kein RAM-/
SSD-/Backup-Löschversprechen. Realer Keychain-/signierter Anchor und Appablauf später
separat; CloudKit/Passkey/Teamfunktionen bleiben eigene Pakete.

AbnahmeS2a: exakte S1-Formatinterop/14 Original-Argon2dateien, echte Dateisystem-
Fehler-/Crash-/Concurrency-/Bounds-/Factor-/Recoveryfälle, Dokumentation/Lizenzen
und unabhängiger Securityreview. Testspeicher oder Compile ist keine Produktfreigabe.

Alle Writer eigener Worktree/Branch; Apple-Statuspflege im Fortsetzungsfenster allein
beim S2a-Agent. Reviewnachweise werden getrennt von ungeprüftem Core integriert.
Alte saubere A1-/A2-Worktrees bleiben Provenienz. Nur eigene kurzlebige Testressourcen,
keine fremden Container/Geräte oder OS-Rechte ändern. Echte Geräte/Signing/alte OS/
interaktive OS-UI ausdrücklich offen. Jobs vor Kontextwechsel im Handoff erfassen.

## A-TF1: offenes CI-Hostgate

Native CI39906842616 ist fehlgeschlagen; die schnelle unveränderte echte
Iconvorprüfung39908555341 reproduziert AssetCatalogAgent-Runtimeabbruch und
fehlende CoreMedia-/MediaToolbox-Symbole auf macOS15/Xcode26.3. Kontrollierter
Hostwechsel auf macos-26 behält Xcode26.3 und sämtliche Produkt-/Icon-/Paketbytes
sowie Mac-/iPad-Prüfungen bei; neuer tatsächlicher Erfolg bleibt abzuwarten.
Fachreview59c7004 und vorhandene signierte Archive/Exporte bleiben Provenienz,
keine Upload-/Einreichungsaktion oder vorweggenommene neue CI-Freigabe.

### A-TF1: tatsächlicher Hostfix-Abschluss

Exakter Korrekturcommit645c8c1: Apple39908768321, Vault39908768308 und
Docs39908768380 sind inzwischen success. Derselbe Xcode26.3 auf macos-26
kompiliert echte Composericons und beide Appziele; App-/Icon-/Paketbytes und
vorhandene signierte Exporte unverändert. Frühere Fehler bleiben historische
Befunde. Enger unabhängiger CI-Diffreview und Mainintegration stehen noch aus;
keine Upload-/Store-/Gerätefreigabe. Details und Einschränkungen im A-TF1-Handoff.
