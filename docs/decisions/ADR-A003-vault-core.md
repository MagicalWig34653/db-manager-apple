# ADR-A003: nativer Tresorkern, Persistenz und unabhängiger Nutzungsanker

Status: **Vorschlag und implementierter S2a-Reviewkandidat**, 23.10.2026.
Keine App-/Credentialoberfläche und keine produktive Anchor-/OS-Freigabe.

## Unveränderter Formatvertrag

S1 wurde im Hauptrepo unabhängig als Formatgrundlage akzeptiert. Der
[Paket-Lock](../../Packages/DBManagerVault/format-lock.json) bindet Originalquelle,
Schema, ASCII-kanonische Bytes, AAD/MAC/KDFregeln und synthetische Go-/Swift-Fixtures.
AES-256-GCM, volle Tags, zufällige Nonces, HKDF/HMAC-SHA256 und festes
Argon2id1.3-Profil 64MiB/t3/p4 bleiben unverändert. [Paketvertrag](../../Packages/DBManagerVault/README.md).
Generation/Revision/Epoch bleiben UInt32 ohne Umbruch. Kein Dateifeld wird als
vertrauenswürdiger aktueller Zähler oder Anker ausgegeben.

## Anker ist eine zwingende getrennte Vertrauensgrenze

`VaultAnchorStore` verlangt dauerhafte atomare Compare-and-Swap-Schritte mit
einer unabhängig gepinnten lokalen Slotzuordnung. Nicht geheime Metadaten:
VaultID, bestätigte Epoch/Generation/SHA256, monotone CAS-Sequenz, lebenslange
Nutzungsreservierungen je Epoch sowie genau ein Pendingvorgang mit Tempname und
gegebenenfalls vorbereitetem Zielhash. Provider müssen auch Metadatengröße und
Persistenz begrenzen; S2a akzeptiert höchstens64 Epochzähler und gültige UInt-Grenzen.

**S2a liefert keinen produktiven Provider.** `SyntheticAnchor` steht nur im
Testtarget; `SyntheticDiskAnchor` nur im separaten Crash-Prüfwerkzeug, das erst in
einer temporären Paketkopie zum Testexecutable wird. Kein stiller Fallback, keine
Keychainänderung/-probe, keine behauptete signierte Zugriffsgruppe/ACL. Der abstrakte
Vertrag macht einen vom Aufrufer gelieferten Dateispeicher nicht vertrauenswürdig.

Ein gültiger alter Tresor allein wird bei festgehaltenem bestätigtem Anker abgelehnt.
Wer Datei **und** Testanker zusammen zurückspielt, wird absichtlich nicht erkannt;
das ist ausdrücklich getestet und keine Produktfreigabe. Auch Keychain mit
`ThisDeviceOnly` ist nicht automatisch ein hardwaregestützter monotoner Zähler:
Apple beschreibt fehlende Migration auf andere Geräte, aber mögliche Wiederherstellung
auf demselben Gerät. S2b muss die konkrete Backup-/Restore-/Signatur-/Zugriffsgruppe
und Aktualitätsgrenze unabhängig belegen oder schreibende Produktpersistenz sperren.
Ein fehlender Anker darf keinen vorhandenen Tresor still einschreiben.

## Reservierung und Commitfolge

Für jede Epoch gilt konservativ maximal2^20 reservierte Root-AEAD-Verschlüsselungen.
Ein Entry-Key-Wrap zählt eins; Create/Rotation zählen zusätzlich beide Root-Hüllen
mit, obwohl diese unter separaten KEKs liegen. Entschlüsselung/HMAC sind keine
Nonce verbrauchenden Verschlüsselungen. Auch gelöschte Einträge und verworfene
Schreibversuche erstatten niemals Nutzung. Jede neue Revision nutzt neue Schlüssel.

1. Vor der ersten geplanten Verschlüsselung: dauerhafter Anker-CAS reserviert
   vollständige geplante Nutzung und einen zufälligen Tempnamen. Neue Tresore
   erhalten zunächst eine zufällige gepinnte ID; noch keine Nutzdatei.
2. Kandidat erstellen, alle Formate/Limits prüfen, private Tempdatei exklusiv
   anlegen, vollständig schreiben, Datei und Verzeichnis `fsync`.
3. Zweiter dauerhafter CAS ergänzt exakten vorbereiteten Zielhash/Epoch/Generation.
4. Alten bestätigten Dateistand erneut vergleichen, Tempbytes rücklesen und ihren
   Hash prüfen, dann atomarer `renameat` im selben gehaltenen Rootdescriptor.
5. Verzeichnis `fsync`, endgültige Dateibytes rücklesen und exakt gegen den
   vorbereiteten Snapshot prüfen. Erst danach finaler dauerhafter CAS auf aktiv,
   Pending löschen; erst nach dessen Erfolg Rückgabe eines bestätigten Commits.

Jeder unklare I/O-/CAS-/Abbruchfehler sperrt die Session und ist möglicherweise
bereits wirksam. Kein Fehler bedeutet automatisch Rollback. Auch eine nach
Finalisierung verlorene Antwort kann einen bereits bestätigten neuen Stand haben.

Bei erneutem Öffnen sind nur zwei Dateiinhalte zulässig: exakt bestätigter alter
oder exakt im unabhängigen Anker vorbereiteter neuer Snapshot. Alter Inhalt beendet
den unbestätigten Vorgang konservativ ohne Nutzungserstattung; Tempdatei entfernen.
Neuer Inhalt wird nach erneutem Verzeichnissync finalisiert. Andere Inhalte,
fehlender bestätigter Stand oder ungültige Metadaten werden abgelehnt, nicht durch
irgendein Backup/Tempfile überschrieben. Erst danach Faktor-/Manifest-/Entryprüfung;
kein Teilklartext. Ein abgebrochener Create ohne Datei kann neu beginnen, verbrauchte
Reservierungen bleiben konservativ erhalten. Neue dabei verworfene Rootkeys werden
nie wiederverwendet. Höchstens64 Epochs; danach explizite Migration neuer Identität.

## Rotation, Recovery, Import und Verlust

Budgeterschöpfung blockiert weitere normale Updates. Bewusste Rotation benötigt
beide erneut nachgewiesenen bisherigen Faktoren und erzeugt neue Root-/Entrykeys,
Epoch und Hüllen. Beide frisch erstellten Faktorwege werden vor Persistenz wieder
entschlüsselt. Generation und Eintragsrevision wachsen auch dabei weiter.
Fehlgeschlagene Rotationen reservieren konservativ Nutzung in der Zielepoch;
der nächste Versuch erhält wieder frischen Root statt einen verworfenen zu nutzen.

Ist ein bisheriger Faktor verloren, darf ein vorhandener alter Faktor weiter
entschlüsseln. Explizite Migration erstellt eine **neue Identität**, neue Root- und
Entrykeys, neues vom Aufrufer gewähltes Passwort, neuen zufälligen Recoverycode
und frischen Anker. Das neue Passwort darf nicht den alten Tresor öffnen. Beide
neuen Wege müssen rückgelesen werden; Originaldatei erhalten. Ein unbekannter alter
Faktor wird nie aus einem anderen nachgebildet. Portable Importe ohne Anker geben
keine Aktualitätszusage; sie migrieren zu neuen Schlüsseln/Zählern statt alte
Rootnutzung ungeprüft auf Null zu setzen.

Alte Kopien bleiben mit alten Faktoren entschlüsselbar. Kompromittierte echte
Datenbankcredentials müssen am Ziel rotiert werden. Verlust beider Faktoren oder
der Ciphertexte ist kein kryptografisch reparierbarer Zustand. `lock` verwirft
Referenzen, garantiert keine Löschung aus Swiftkopien/RAM/Swap/SSD/Backups.

## Dateisystem- und Prozessgrenzen

Der Aufrufer übergibt einen bereits privaten existierenden Root0700. Jede absolute
Pfadkomponente wird mit `openat/O_DIRECTORY/O_NOFOLLOW` traversiert; keine stille
Symlinkauflösung. Deskriptor bleibt gehalten. Slotnamen sind nur32 kleine Hexzeichen,
Datei-/Tempnamen vom Paket verwaltet. Reguläre Dateien0600, eigene UID, `nlink=1`,
Nonblocking-Open und Fstatprüfung; keine fremden Modi oder ACLs werden repariert.
Exklusiver nicht wartender `flock` auf privatem Lockfile für die ganze Session.
Ein Actorvorgang ohne Reentranz; ein Argon2-Aufruf je Prozess durch Mutex.

Dies koordiniert kooperative Instanzen. Kein Schutz gegen beliebige gleichberechtigte
oder privilegierte OSwriter, die Locks ignorieren, Lockinodes austauschen, Anker oder
Prozessspeicher kontrollieren. Hash-/Rückleseprüfungen verhindern falsche Erfolgsmeldung
für dabei erkannte geänderte Bytes; keine Racefreiheit gegen beliebige Änderung nach
der letzten Prüfung oder nach erfolgreichem Commit. Private Modi sind kein belegter
App-Sandbox-/FileProtection-/Backupschutz. `fsync`/Rename und echte Prozessabbrüche
beweisen kein Stromausfall-/Hardware-/Netzwerkfilesystemverhalten. Nur lokaler
verwalteter Datenträger ist Arbeitsziel; kein Sync-/Netzlaufwerk freigegeben.

Datei8MiB,64 Einträge,64KiB Nutzdaten je Eintrag, feste KDFparameter vor teurer
Arbeit prüfen. Nicht kooperativer KDF läuft begrenzt zu Ende; Cancellation vor/nach
KDF und zwischen Schreibphasen, keine Sofortstopp-/Gesamtprozess-RAM-/DoSgarantie.
Die spätere Oberfläche muss Aufträge begrenzen und Schlüsselzustände sichtbar machen.

## Quellen und verbleibende Gates

- [S1-Normativquelle](https://github.com/MagicalWig34653/db-manager/blob/1a4eb3c78d22b2fc264b3bce57128d69584735ba/docs/security/VAULT-FORMAT-V1.md)
- [Argon2-Referenzpin](https://github.com/P-H-C/phc-winner-argon2/tree/f57e61e19229e23c4445b85494dbf7c07de721cb)
- [Apple: Keychain-Zugänglichkeit/Restoregrenzen](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
- [Apple: ThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Apple: Authentifizierungsdialog unterbinden](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail)

Diese Primärquellen sind Plattformdokumentation, keine eigenen OS-/Signaturproben.
Unabhängige S2a-Core-QA, tatsächlicher produktiver Anker, App-/Recovery-/Backupablauf,
signierte Sandbox und echte Zielgeräte bleiben Gates. Keine CloudKit-/Passkey-/
Team-/SSHfunktion. [Tatsächliche Prüfungen und offene Jobs](../handoffs/S2a.md).
