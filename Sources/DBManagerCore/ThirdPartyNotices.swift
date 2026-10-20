// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum ThirdPartyNotices {
    public static var text: String {
        guard let root = Bundle.module.url(forResource: "ThirdParty", withExtension: nil),
              let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] else {
            return "Lizenzhinweise konnten nicht geladen werden."
        }
        return paths.sorted { $0.path < $1.path }.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let name = String(url.path.dropFirst(root.path.count + 1))
            return name + "\n\n" + text
        }.joined(separator: "\n\n────────────────────\n\n")
    }
}
