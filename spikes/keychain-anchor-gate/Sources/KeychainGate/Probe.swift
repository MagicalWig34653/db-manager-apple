// SPDX-License-Identifier: AGPL-3.0-only
// Isolated synthetic OS admission probe. No production anchor or app integration.
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

struct Item: Sendable {
    let service = "org.dbmanager.synthetic-anchor-gate." + UUID().uuidString
    let account = "synthetic-" + UUID().uuidString
    func query() -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true,
                kSecUseAuthenticationContext as String: context]
    }
    func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    func swap(expected: Data, replacement: Data) -> OSStatus {
        var query = query()
        query[kSecAttrGeneric as String] = expected
        return SecItemUpdate(query as CFDictionary,
            [kSecAttrGeneric as String: digest(replacement), kSecValueData as String: replacement] as CFDictionary)
    }
}
final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OSStatus] = []
    func append(_ value: OSStatus) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    func snapshot() -> [OSStatus] { lock.lock(); defer { lock.unlock() }; return values }
}
@main struct Probe {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let receipt = URL(fileURLWithPath: CommandLine.arguments[1])
        let item = Item()
        var report: [String: Any] = ["synthetic_only": true, "service": item.service, "account": item.account,
            "data_protection_explicit": true, "synchronizable_requested": false,
            "interaction_allowed": false, "cas_tested": false, "os_lock_tested": false,
            "uncertain_ack_tested": false, "created_confirmed": false, "gate": "pending"]
        func save() throws {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            try data.write(to: receipt, options: .atomic)
        }
        // Save exact own identity BEFORE any call whose outcome might be uncertain.
        try save()
        let initial = Data("{\"sequence\":1,\"synthetic\":true}".utf8)
        var add = item.query()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrGeneric as String] = item.digest(initial)
        add[kSecValueData as String] = initial
        let status = SecItemAdd(add as CFDictionary, nil)
        report["create_status"] = status
        guard status == errSecSuccess else {
            let denied = [errSecMissingEntitlement, errSecInteractionNotAllowed, errSecNotAvailable,
                          errSecAuthFailed, errSecParam, errSecDuplicateItem].contains(status)
            report["gate"] = denied ? "blocked_os_admission" : "uncertain_create_outcome"
            report["cleanup_needed"] = !denied
            try save()
            print("OS admission blocked: \(status). No fallback, no item update/delete attempted.")
            exit(2)
        }
        report["created_confirmed"] = true
        var code: Int32 = 3
        do {
            try save()
            var read = item.query()
            read[kSecReturnData as String] = true
            read[kSecReturnAttributes as String] = true
            read[kSecMatchLimit as String] = kSecMatchLimitOne
            var output: CFTypeRef?
            let readStatus = SecItemCopyMatching(read as CFDictionary, &output)
            report["read_status"] = readStatus
            guard readStatus == errSecSuccess, let attributes = output as? [String: Any],
                  attributes[kSecValueData as String] as? Data == initial,
                  attributes[kSecAttrGeneric as String] as? Data == item.digest(initial),
                  attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                  attributes[kSecAttrSynchronizable as String] as? Bool == false else { throw ProbeError.failed }
            let replacement = Data("{\"sequence\":2,\"synthetic\":true}".utf8)
            let wrong = item.swap(expected: Data(repeating: 0, count: 32), replacement: replacement)
            report["wrong_expected_status"] = wrong
            guard wrong == errSecItemNotFound else { throw ProbeError.failed }
            let results = Results()
            DispatchQueue.concurrentPerform(iterations: 2) { number in
                let data = Data("{\"sequence\":2,\"writer\":\(number),\"synthetic\":true}".utf8)
                results.append(item.swap(expected: item.digest(initial), replacement: data))
            }
            let statuses = results.snapshot()
            report["cas_statuses"] = statuses
            guard statuses.filter({ $0 == errSecSuccess }).count == 1,
                  statuses.filter({ $0 == errSecItemNotFound }).count == 1 else { throw ProbeError.failed }
            report["cas_tested"] = true
            report["gate"] = "crud_cas_passed_remaining_platform_gates_open"
            code = 0
        } catch {
            report["gate"] = "blocked_read_or_atomic_cas"
        }
        // Delete only the exact identity whose ADD this process confirmed successful.
        let cleanup = SecItemDelete(item.query() as CFDictionary)
        report["cleanup_status"] = cleanup
        report["cleanup_needed"] = cleanup != errSecSuccess
        if cleanup != errSecSuccess { report["gate"] = "cleanup_pending"; code = 3 }
        try save()
        print("Synthetic probe ended; exact own cleanup status: \(cleanup). No production approval.")
        exit(code)
    }
    enum ProbeError: Error { case failed }
}
