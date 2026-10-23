# Handoff G-S2b

23.10.2026, Branch spike/keychain-anchor-gate ab d0dea67. Besitz ausschließlich
spikes/keychain-anchor-gate und neue Sicherheits-/Handoffdokumente. Kein App-,
Xcode-, Root-Package- oder Vault-Core-Produktbyte geändert.

Auftrag: endlicher nichtinteraktiver OS-Nachweis. Ergebnis **blockiert**, keine
Produktfreigabe. [Grenzen und Primärquellen](../security/G-S2b-keychain-gate.md).

```sh
python3 spikes/keychain-anchor-gate/check.py
python3 spikes/keychain-anchor-gate/check.py --run --output /tmp/keychain-gate-result.json
python3 scripts/check-docs.py
```

Frischer Build bestanden; tatsächlicher Lauf Exit2, SecItemAdd=-34018,
errSecMissingEntitlement. Eigener Host ad hoc, keine Team-ID. DP explizit,
Sync=false, WhenUnlockedThisDeviceOnly, LA-Interaktion verboten.
[Aufnahme](../../spikes/keychain-anchor-gate/results/macos-admission.json).

Kein Item bestätigt erstellt, danach kein weiterer Itemzugriff. Keine alten Items,
ACLs, Truststores oder OS-Rechte verändert; keine Dialoge, kein Fallback. Eigene
Build-/Quittungsverzeichnisse des Aufrufs entfernt. Keine laufenden Probejobs.
Nur synthetische öffentliche UUIDs, keine Credentials.

AttrGeneric-CAS-Folgepfad vorbereitet, wegen Aufnahmeverweigerung **ungeprüft**.
Positive CAS-/Durability-/OS-Lock-/Unsicherheitsbelege offen. Keine Hardwaremonotonie
oder OS-/Keychainrollbackabwehr. Keine weiteren Providerschichten implementiert.

Lizenzumfang: eigener AGPL-3.0-only-Code und Apple-Systemframeworks, null externe
Paketabhängigkeiten. Kein zusätzlicher Fremdnotice/Lockfile erforderlich.
Unabhängiger Review vor etwaiger Integration; kein Selbstreview als Produktabnahme.
