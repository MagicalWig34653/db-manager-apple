# DBManagerVault: isolierter nativer Tresorkern

S2a, Entwicklungs- und Reviewkandidat. **Keine Appintegration, produktive
Credentialpersistenz oder produktive Anchorimplementierung.** Swift-Paket mit
System-CryptoKit/Security/Foundation und unveränderter Argon2-C-Referenz.
macOS14/iPadOS17 sind Compileziele, keine geprüften alten Laufzeiten/Geräte.

```sh
python3 scripts/check-vault.py
```

Aufruf aus der Repositorywurzel; das Skript baut/testet ausschließlich dieses Paket,
kompiliert das iPad-Simulatorziel und erzeugt in einem temporären Testpaket sechs
echte abrupte Prozessabbrüche. Nur synthetische Daten, keine App/Simulatorstarts,
OS-Rechte oder globalen Installationen. Das Paket ist ohne ein Geschwisterrepo
mit `swift test --package-path Packages/DBManagerVault` prüfbar.

## Vertrag und Herkunft

[Format-Lock](format-lock.json): unveränderte v1-Bytes aus Hauptrepo
`1a4eb3c78d22b2fc264b3bce57128d69584735ba`, Handoff
`03bd3f40e436efe44dbbdcbbcbb6245e285ad4bf`. Schema-SHA256
`b688656056fe2e23848ce17149bc817609c7369f230a3f49dd91f05db4d3f4dd`.
[Normativer Originalvertrag](Format/docs/security/VAULT-FORMAT-V1.md.txt),
[Schema](Format/contracts/vault-v1.schema.json), öffentliche synthetische Go-/Swift-
Fixtures und AAD sind bytegleich enthalten. Ursprüngliche Markdowntexte haben
zusätzlich `.txt`, damit ihre historischen relativen Links nicht als heutige
lokale Projektlinks missverstanden werden; Inhalt und Hash bleiben unverändert.

Die beiden S1-Swift-Model-/Codecdateien wurden als eigene AGPL-Quellen übernommen.
Modelle/Byte-/AAD-/MAC-/KDFregeln bleiben gleich. Erweiterungen im Codec sind
globale KDF-Serialisierung, Abbruchprüfungen und ein interner Create-Einstieg mit
vorab gebundener Identität. Session-/Writerlogik ist getrennt implementiert.
Keine neue Kryptoprimitive und keine bewegliche Fremdquelle.

## Öffentliche Core-API

- `VaultCodec.parse/unlock`: begrenzter portabler S1-Reader. Ein erfolgreicher
  Readeraufruf allein beweist keine Aktualität oder lokalen Besitzerbezug.
- `VaultSession(root:slot:anchor:)`: Actor mit zwingend vorgegebenem
  `VaultAnchorStore`. Es gibt keinen produktiven Speicher-/Datei-/Keychainfallback.
  `newSlotIdentifier()` erzeugt verwaltete zufällige Dateinamen.
- `beginCreate` reserviert Nutzung vor Verschlüsselung und liefert Recoverymaterial
  nur im Speicher. `records` bleibt bis `confirmCreate` gesperrt. Bestätigung
  entschlüsselt unabhängig mit Passwort und zurückgegebenem Recoverymaterial;
  ein UI-/Papier-/Offlinebackup-Rücklesebeweis ist erst S2b-Aufgabe.
- `open` benötigt einen passenden unabhängigen Anker plus einen gültigen Faktor.
  `update` übernimmt die vollständige geordnete gewünschte Eintragsliste: bekannte
  IDs erhöhen Revision, `nil`-IDs erzeugen neue Einträge, ausgelassene IDs löschen.
  Jede neue Revision erhält neue Datenschlüssel und Nonces. Kein Teilerfolg.
- `rotate` behält beide alten Faktoren nur nach beiden Nachweisen; erneuert Root,
  Datenschlüssel, Hüllen, KDF-Salt und Epoch. Generation/Revisionen wachsen weiter.
- `beginMigration` kann mit einem überlebenden alten Faktor lesen, verlangt ein
  neues Passwort und erzeugt neue Identität/Root/Recovery. Das neue Passwort darf
  den Quelltresor nicht öffnen. Beide neuen Wege müssen vor Persistenz rückgelesen
  werden. Die Quelldatei wird nie beschrieben. Ohne beide alten Faktoren darf
  kein unbekannter alter Faktor unter neuem Root nachgebildet werden.
- `lock` gibt Dateisperre frei und verwirft Klartext-/Schlüsselreferenzen. Swift-
  Kopien, Swap, SSD, Snapshots und Backups werden dadurch nicht sicher gelöscht.

Ein Writer je privatem Root durch exklusiven `flock`, ein nicht reentranter
Actorvorgang je Session, höchstens eine Argon2-Berechnung pro Prozess durch Mutex.
Argon2 selbst ist nicht kooperativ abbrechbar. Abbruch wird vor/nach dieser
begrenzten Berechnung bzw. zwischen Schreibphasen geprüft; keine Sofortstopp-
oder harte I/O-/Wartezeitgarantie. Eine UI muss zusätzlich Aufträge begrenzen.

[ADR-A003](../../docs/decisions/ADR-A003-vault-core.md) beschreibt Anker,
Commit-/Crashzustände, Zähler, Bedrohungsgrenzen und offene Produktgates.
[Lizenzinventar](LIZENZEN.md), [Handoff](../../docs/handoffs/S2a.md).
