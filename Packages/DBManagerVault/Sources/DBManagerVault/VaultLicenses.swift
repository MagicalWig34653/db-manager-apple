// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum VaultLicenses {
    public static func originalTexts() throws -> [String: String] {
        do {
            let base = Bundle.module.resourceURL!.appendingPathComponent("Notices")
            return try Dictionary(uniqueKeysWithValues: ["AGPL-3.0-only.txt", "Argon2-LICENSE.txt"].map {
                ($0, try String(contentsOf: base.appendingPathComponent($0), encoding: .utf8))
            })
        } catch { throw StorageError.io }
    }
}
