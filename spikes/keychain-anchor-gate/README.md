# G-S2b: nichtinteraktives Keychain-Plattformgate

Isolierte synthetische OS-Probe, kein produktiver Anchor. Eigener Code AGPL-3.0-only
wie die Repositorylizenz; keine externen Pakete oder kopierten Fremdquellen.
Security, LocalAuthentication und CryptoKit sind Systemframeworks. Kein künstliches
Package.resolved bei null Fremdabhängigkeiten.

```sh
python3 spikes/keychain-anchor-gate/check.py
python3 spikes/keychain-anchor-gate/check.py --run --output /tmp/keychain-gate-result.json
```

Standardaufruf kompiliert ausschließlich. `--run` erlaubt nur frisch zufällig
benannte synthetische Items. Erwarteter Exitcode dieser Umgebung: 2, weil
SecItemAdd mit errSecMissingEntitlement (-34018) abgelehnt wird. Ein anderer Host
kann anders reagieren. Kein Fallback, keine Dialoge, keine fremden Items lesen.

[Aufgenommener tatsächlicher Befund](results/macos-admission.json),
[Plattformgrenzen und Primärquellen](../../docs/security/G-S2b-keychain-gate.md),
[Handoff](../../docs/handoffs/G-S2b.md).

Nach bestätigtem Add enthält die Probe einen AttrGeneric-gefilterten Updateversuch
mit falschem Erwartungswert und zwei konkurrierenden Schreibern. **Dieser Codepfad
wurde hier nicht erreicht und ist kein CAS-Nachweis.** Auch OS-Lockzustände und
verlorene Bestätigungen wurden nicht geprüft. Ein etwaiger erfolgreicher CRUD/CAS-
Pfad lässt diese weiteren Gates ausdrücklich offen.

Vor dem ersten OS-Aufruf wird eine lokale Quittung mit exakter eigener Identität
angelegt. Bei unsicherem Ausgang/Timeout bleibt sie erhalten. Die Probe löscht nur
nach selbst bestätigtem Add die exakte eigene Identität; keine globale Bereinigung.
Ein Clienttimeout belegt weder Rollback noch Nichtexistenz eines Items.
