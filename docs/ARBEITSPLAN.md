# Arbeitsplan

Stand: 20.10.2026. Lead koordiniert und pflegt zentrale Statusdateien;
Architecture/Security-Agent übernimmt zugleich die fachliche Apple-Rolle.

| ID | Auftrag | Status | Abnahme |
| --- | --- | --- | --- |
| P0 | Eigenständiges öffentliches Repo, Lizenz/Agent-Einstieg/CI | abgeschlossen | öffentliche main-Commits und Docs-CI |
| A1 | Eigenständiger nativer SQLite-/SwiftUI-Arbeitsplatz | nach QA und CI integriert; UI-Lifecyclefix geschlossen | zehn Swift-Tests, Mac-/Simulatorbuild, Sicherheitsproben; Handoff |
| A2 | Weiterer nativer Produktpfad / optionaler Backendclient | noch zu beauftragen | vorher eigener begrenzter Auftrag und Vertragsstand |
| S1 | Produktiver Tresor/Recovery/Sync | offen | Sicherheitsstufen im Hauptrepo; keine Freigabe aus A1 ableiten |

Worktree `.worktrees/apple-workbench`, Branch `feat/apple-workbench`, bleibt saubere
Provenienz. Keine eigenen App-/Simulatorjobs offen. Echte Geräte, signierte Sandbox,
Distribution und interaktiver OS-UI-Smoke bleiben ausdrücklich offen.
Gemeinsame Integration und nächste Tickets stehen im Hauptrepo-Arbeitsplan.
