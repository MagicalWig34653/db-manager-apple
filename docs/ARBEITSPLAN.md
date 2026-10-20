# Arbeitsplan

Stand: 20.10.2026. Lead koordiniert, organisiert unabhängige Reviews, integriert und
pflegt zentrale Statusdateien. Agents implementieren. Gesamtzeitgrenze im Hauptrepo:
21.10.2026 04:00 Europe/Berlin (=02:00 UTC) oder vorher vollständiger Abschluss.

| ID | Auftrag | Tatsächlicher Stand und Abnahme |
| --- | --- | --- |
| P0 | Eigenständiges öffentliches Repo, Lizenz und Agent-Einstieg | abgeschlossen |
| A1 | Eigenständiger nativer SQLite-/SwiftUI-Arbeitsplatz | nach QA und CI integriert; zehn Tests, Mac-/Simulatorbuild, Lifecyclefix geschlossen |
| A2 | Direkter PostgreSQL-Pfad ohne Go, SQLite erhalten | Quellen89b2683/abaa3dc/b72e62c nach unabhängigem Review und exakter grüner CI integriert als fdd533e/cd5d886/031b1e8; Kalenderbefund geschlossen, konkreter NIOssl-Pin akzeptiert. Leadintegrationsprüfung bestanden; neue Main-CI noch kontrollieren. |
| S2a | Eigenständiger Vault-Core ohne Appverdrahtung | aktiv, feat/vault-core, .worktrees/vault-core, Basis7cbeb38; neuer begrenzter Core mit eigenständiger unabhängiger Abnahme |
| S2b | Produktiver Anchor und App-/Recoveryablauf | noch nicht beauftragt; S2a-QA und praktische Plattform-/Sicherheitsgates Voraussetzung |

S2a-Dateibesitz: nur neues Packages/DBManagerVault samt Tests/Fixtures/Originaltexten/
Locks, eigene Vault-CI/Skripte, neue Sicherheitsdokumente/ADR-A003/HandoffS2a. Keine
App-/Xcode-/Rootpackage-/DBManagerCore-/A2-/zentralen Statusänderungen. Actor-Session,
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

Alle Writer eigener Worktree/Branch; zentrale STATUS/ARBEITSPLAN beim Lead.
Alte saubere A1-/A2-Worktrees bleiben Provenienz. Nur eigene kurzlebige Testressourcen,
keine fremden Container/Geräte oder OS-Rechte ändern. Echte Geräte/Signing/alte OS/
interaktive OS-UI ausdrücklich offen. Jobs vor Kontextwechsel im Handoff erfassen.
