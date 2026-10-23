# S2a-Lizenz- und Herkunftsinventar

Eigene Paket-/Binding-/Session-/Writer-/Test-/Skriptdateien: **AGPL-3.0-only**.
Übernommene fremde Dateien behalten unveränderte Copyrights und Lizenzen.

| Anteil | Feste Quelle | Lizenz/Nachweis |
| --- | --- | --- |
| S1-Modelle/Codec/Format/Fixtures | [Hauptrepo Commit 1a4eb3c](https://github.com/MagicalWig34653/db-manager/tree/1a4eb3c78d22b2fc264b3bce57128d69584735ba/spikes/vault-interop/swift) | Eigener AGPL-3.0-only-Code; Formatkopien/Fixturehashes im [Format-Lock](format-lock.json), Original-AGPL in [Format/LICENSE](Format/LICENSE) |
| Argon2-C | [Offizieller Commit f57e61e](https://github.com/P-H-C/phc-winner-argon2/tree/f57e61e19229e23c4445b85494dbf7c07de721cb) | Apache-2.0 aus ursprünglichem CC0-/Apache-Dualangebot gewählt. [Original-LICENSE](Vendor/argon2/LICENSE) einschließlich beider Texte bytegleich erhalten; [14 Originalhashes](Vendor/argon2/upstream-lock.json) mechanisch geprüft |
| CryptoKit/Security/Foundation/Darwin | Systemframeworks der vorhandenen Apple-SDKs | Apple-SDK-/Systemruntimebedingungen, keine vendorten/weiterverteilten Frameworkkopien |
| Swift/Swift Testing | vorhandene Toolchain | Toolchainbedingungen, kein entferntes Swift-Paket hinzugefügt |
| Python-Standardbibliothek | vorhandenes Python3, nur Prüfsystem | Toolchainbedingungen, keine vendorte Pythonruntime/Abhängigkeit |

Argon2-Quellbytes sind unverändert; `ref.c` und `ARGON2_NO_THREADS` sind dieselbe
Buildauswahl wie S1. Vier algorithmische Lanes bedeuten keine vier C-Workerthreads.
Kein Go-Code, PostgresNIO, BoringSSL oder anderes entferntes Swift-Paket gehört
zu diesem isolierten Paket. Daher entsteht kein `Package.resolved`; feste Locks
sind der Vendor-Lock und der Format-Lock. Kein künstlich erzeugtes Leer-Lockfile.

Eigene vollständige AGPL und ursprüngliche Argon2-LICENSE werden als Paketressourcen
mitgeliefert und sind über `VaultLicenses.originalTexts()` zugänglich; der Test
prüft auch ihren tatsächlichen Runtimezugriff. Der Prüflauf vergleicht Quell-/
Ressourcenbytes. Künftiges Appbundle und Distribution sind nach tatsächlicher
Einbindung nochmals zu prüfen; S2a behauptet kein heute vorhandenes Vault-Appbundle.
Kein allgemeines juristisches Freigabeurteil aus diesem Inventar.
