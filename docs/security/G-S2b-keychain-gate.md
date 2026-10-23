# G-S2b: OS-Ankergate blockiert

Stand 23.10.2026. Grundlage: [ADR-A003](../decisions/ADR-A003-vault-core.md).
Isolierte synthetische Probe, keine Appintegration, Credentialpersistenz oder
Formatänderung. [Maschinenlesbarer Befund](../../spikes/keychain-anchor-gate/results/macos-admission.json).

## Tatsächliche Prüfung

Frischer Swift-6-Build auf macOS27.0.1/arm64 bestanden. Eigener Probehost ad hoc
signiert, ohne TeamIdentifier. SecItemAdd verweigert die Aufnahme mit
**errSecMissingEntitlement (-34018)**, gemäß tatsächlichem SDK-Header
Security/SecBase.h. Explizit DP-Keychain, Synchronizable=false,
WhenUnlockedThisDeviceOnly und LAContext.interactionNotAllowed=true.
Kein Item bestätigt erstellt; anschließend kein Read, Update oder Delete.
Keine fremden Items gesucht, ACLs, Truststores, Systemrechte oder Entsperrungen
verändert. Keine Benutzerinteraktion angefordert, kein Schlüsselbundfallback.

## Offener Providervertrag

Eine Bibliothek verleiht ihrem Host keine Zugriffsberechtigung. Erforderlich ist
später ein tatsächlich passend signierter/provisionierter Apphost mit belegten
Keychainberechtigungen. Appdeklaration und Simulatorcompile ersetzen diesen
Nachweis nicht. Keine Signingidentitäten anderer Nutzer inventarisiert.

CAS muss EIN OS-Update mit erwartetem AttrGeneric-Token und gemeinsamem Update
von AttrGeneric/ValueData sein. Kein ValueData-Queryfilter und kein Read-Modify-
Unconditional-Write. Das Probeprogramm bereitet SHA256 synthetischer Recordbytes
als Token vor: falscher Erwartungswert muss NotFound ergeben, zwei konkurrierende
Schreiber genau einen Gewinner. Dieser Pfad wurde **nicht erreicht**. Code ist
kein Beleg atomarer OS-Semantik oder dauerhafter Speicherung.

Weitere offene Belege: tatsächlich rückgelesene Accessibility/Nicht-Synchronisierung,
mehrere Prozesse, verlorene Bestätigung/Prozessabbruch/Pending-Recovery sowie
OS-Lock/Unverfügbarkeit ohne Dialog. OS-Locks wurden nicht erzwungen. Kein
produktiver InMemory-/Dateiersatz und keine Appsecretpersistenz freigegeben.

## Vertrauensgrenze

Ein aktueller unabhängiger OS-Anker könnte das Rückspielen allein der Tresordatei
gegen bestätigte Generation/Hash und vorab verbrauchte Reservierungen erkennen.
Diese Aussage setzt Integrität und Aktualität des Ankers voraus. ThisDeviceOnly
ist keine Hardwaremonotonie: gleichzeitiges OS-/Keychainrestore kann den Anker
zurücksetzen. Kein Schutz gegen vollständig kompromittiertes OS, gleichberechtigte
bösartige OS-Prozesse oder kompletten Backuprollback. Kein sicherer RAM-/SSD-
Löschbeleg. Fehlender/unsicherer Anchor darf keine alte schreibende Session
freigeben; Import/Migration in einen frischen Tresor bleibt gesondert abzustimmen.
Ein zurückrollbarer Zähler beweist keine lebenslange Root-AEAD-Nutzung.

## Primärquellen

- [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains):
  DP-Keychain, Nutzerkontext, hostseitige Signing-/Profil-/Accessgroupgrenzen.
- [Apple DTS SecItem Fundamentals](https://developer.apple.com/forums/thread/724023):
  Abfrage-/Updateattribute; ValueData ist kein unterstütztes Queryattribut.
- [SecItemUpdate](https://developer.apple.com/documentation/security/secitemupdate%28_%3A_%3A%29)
  und [AttrGeneric](https://developer.apple.com/documentation/security/ksecattrgeneric):
  Grundlage eines zu prüfenden attributgefilterten Updates, kein hier bestandener CAS-Beleg.
- [LAContext.interactionNotAllowed](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed)
  und [Authentifizierungskontext](https://developer.apple.com/documentation/security/ksecuseauthenticationcontext):
  nichtinteraktive Fehlerbehandlung statt Dialog.
- [Accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
  und [WhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly):
  Zugriffsklasse und Gerätemigration, keine universelle Rollbackgarantie.

Primärquellen beschreiben APIs und Grenzen; positive Plattformbeweise fehlen.
