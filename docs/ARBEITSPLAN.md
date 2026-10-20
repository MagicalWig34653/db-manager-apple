# Arbeitsplan

Stand: 20.10.2026. Lead koordiniert und pflegt zentrale Statusdateien;
Architecture/Security-Agent übernimmt zugleich die fachliche Apple-Rolle.

| ID | Auftrag | Status | Abnahme |
| --- | --- | --- | --- |
| P0 | Eigenständiges öffentliches Repo, Lizenz/Agent-Einstieg/CI | abgeschlossen | öffentliche main-Commits und Docs-CI |
| A1 | Eigenständiger nativer SQLite-/SwiftUI-Arbeitsplatz | nach QA und CI integriert; UI-Lifecyclefix geschlossen | zehn Swift-Tests, Mac-/Simulatorbuild, Sicherheitsproben; Handoff |
| A2 | Direkter PostgreSQL-Pfad ohne Go, SQLite erhalten | beauftragt: `feat/apple-postgres`, `.worktrees/apple-postgres`, Basis `ce0aedb` | Echte TLS-Positiv-/Negativproben, Einzelstatement/DB-erzwungenes Readonly und ausdrückliche Schreibfreigabe, verlustarme begrenzte Ergebnisse, tatsächliche DB-Freigabe nach Abbruch, sichere Quellenwechsel; Mac-/iPad-Zielbuild, eigenständige QA und CI vor Integration |
| S2 | Produktiver Tresor/Recovery, Sync separat | noch nicht beauftragt | S1-Format im Hauptrepo unabhängig abgenommen; Persistenz/Recoveryablauf/Crash-/Schlüsselzustände/Zielgeräte bleiben eigene Gates |

Worktree `.worktrees/apple-workbench`, Branch `feat/apple-workbench`, bleibt saubere
Provenienz. Keine eigenen App-/Simulatorjobs offen. Echte Geräte, signierte Sandbox,
Distribution und interaktiver OS-UI-Smoke bleiben ausdrücklich offen.
Gemeinsame Integration und nächste Tickets stehen im Hauptrepo-Arbeitsplan.

A2-Dateibesitz: Produktmodule/SwiftUI, Package/Lock/Xcode/Entitlements, eigene Tests/
CI/Skripte, Lizenzinventar mit Originaltexten, README/Einrichtung/ADR und
`docs/handoffs/A2.md`. STATUS und ARBEITSPLAN bleiben beim Lead. Zugangsdaten nur
im Speicher; keine System-Truststores/Keychain-/OS-Berechtigungen verändern und
keine fremden Container/Simulatoren berühren. Physische Geräte/Signing/interaktive
OS-UI nicht aus Compile-/ViewModelproben ableiten.
