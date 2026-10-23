# Arbeitsplan

Stand: 23.10.2026. Neuer ausdrücklicher Abschluss: erster Build auf TestFlight,
Pages live sowie vollständig nachgezogene Dokumentation und Claude-Code-Übergabe.
Root koordiniert ausschließlich; Agents übernehmen die freigegebenen Schritte.
Dies bedeutet keine vollständige Umsetzung aller Produktfunktionen.
[STATUS](STATUS.md) führt tatsächliche Ergebnisse/Grenzen.

## Integrierte Pakete

| Paket | Tatsächlicher Stand | Nachweis/Grenze |
| --- | --- | --- |
| A1 | Eigenständiger SQLite-/SwiftUI-Arbeitsplatz | Unabhängiger Lifecycle-/Securityreview, Mac-/Simulatorbuilds; echte Geräte separat |
| A2 | Direkter PostgreSQL-Pfad ohne Go, SQLite erhalten | TLS-/Readonly-/Write-/Abbruch-/Präzisionsfälle, Kalenderfix und konkrete NIOssl-Pinakzeptanz unabhängig geprüft |
| S2a | Isolierter Vault-Core | Format/Originalpins/Dateisystem/CAS/Pending/Recovery geprüft; kein produktiver Anchor oder App-Geheimnisspeicher |
| A-TF1 | Registrierte Bundle-IDde.linolaske.dbmanager,0.1.0Build1, signierte Archive/lokale IPA-/PKG-Exporte und echtes Composericon | Vollständige Quellen bis6551a8a als7f5282e und Review7e6619e als9a15581 nach konkreter Freigabe integriert; exakte645-CIs grün, neue Main-CIs noch kontrollieren |

## Aktueller Releaseabschluss

1. Neue drei Main-CIs am abschließenden Integrationscommit kontrollieren. Geprüfte
   App-/Icon-/Xcode-/Sources-/Package-/Distributionbytes unverändert; keine alte
   vollständige Build-/Archive-/Exportmatrix ohne Ursache wiederholen.
2. Endgültige IPA/PKG und zugehörige Archive sind zusätzlich dauerhaft privat im
   lokalen Developerbereich gesichert, SHA-/Dateibaumgleichheit bestätigt und
   lokale Receipt/README vorhanden. Originale erhalten, keine überschriebenen
   abweichenden Dateien, keine Profile/Keys/Artefakte in öffentliche Assets kopieren.
3. Betreiberangaben zu Verschlüsselung, Privacy und TestFlightmetadaten konkret
   abschließen. Kein blindes NO für Encryption, keine serverseitige ASC-/TestFlight-
   Verarbeitung aus lokalem Export ableiten. Nutzer hat ASC-EintragDBManager erstellt.
4. Der Nutzer hat den ersten TestFlight-Upload inzwischen ausdrücklich beauftragt;
   der dedizierte Delivery-Agent übernimmt ihn separat und weist den tatsächlich
   verarbeiteten Build nach. Dieser Integrationsschritt hat nichts hochgeladen.
   Kein App-Store-Release oder öffentliche externe Einladungen. Signaturen ersetzen
   keine physischen Geräte-/Runtime-Sandbox-/OSdialogprüfungen.

## Weitere getrennte Pakete

- G-S2b: tatsächlicher damaliger ad-hoc-DP-Keychainfehler-34018 bleibt dokumentiert;
  kein Item, keine CAS-/Lock-/Unsicherheitsfreigabe oder automatischer Produktfallback.
  Ein geeigneter signierter/provisionierter Host muss separat geprüft werden.
- C-Export1/A3: gemeinsame Root-/Web-/Apple-Exportsemantik mit Herkunft/Schema/
  Fixtures unabhängig abstimmen; nativer Ergebnisexport erst als eigenes Paket.
- Weitere direkte Treiber, Schemafunktionen, Import/Export, persönliche Speicherung,
  Passkeys/CloudKit und Teams bleiben Bestandteil des Hauptprojektziels, getrennte
  Abnahme statt pauschaler Paritäts-/Releasebehauptung.

AppleSTATUS/Plan sind für diesen begrenzten Release exklusiv beim Releasekoordinator.
Andere Worker schreiben nicht parallel; neue Zuweisung durch Root. Root- und Web-
Statusdateien haben andere Owner. Jeder Writer eigener Branch/Worktree, unabhängiger
Review vor Integration. Deutsch UI/Dokumentation, Englisch Code/Tests/Bezeichner,
AGPL-3.0-only eigener Code, Originaltexte und Gitidentität erhalten.

Keine fremden Container/Geräte/Systemrechte/Truststores/Keychainitems verändern.
Nur eigene kurzlebige Fixtures/Scratchs bereinigen, niemals die absichtlich gesicherten
Benutzerarchive. Vor Zeitgrenze Dateien/Commit, Tests/Befunde, unintegrierte Arbeit,
laufende eigene Jobs und nächsten Schritt im Handoff sichern. [Releasehandoff](handoffs/A-TF1-integration.md).
