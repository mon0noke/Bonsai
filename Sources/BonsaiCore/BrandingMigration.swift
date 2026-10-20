import Foundation
import Darwin

/// Retired identifiers exist only here to preserve existing user data and protect
/// the original recovery copies. All new writes use AppIdentity.
public enum BrandingMigration {
    static let retiredPrefixes = ["app.ottercare.", "app.ottocare."]
    static let retiredFolderNames = ["Otter", "Otto"]
    public static let retiredDefaultsDomain = "app.ottercare.mac.nature"
    private static let preferencesMarker = "bonsai.preferencesMigrated.v1"

    public static func run(defaults: UserDefaults = .standard,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           domain: String = AppIdentity.bundleIdentifier,
                           previousDomain: String = retiredDefaultsDomain) {
        // Merge once, preserving every preference already saved under Bonsai.
        var destination = defaults.persistentDomain(forName: domain) ?? [:]
        if destination[preferencesMarker] as? Bool != true {
            let previous = defaults.persistentDomain(forName: previousDomain) ?? [:]
            for (key, value) in previous where destination[key] == nil { destination[key] = value }
            destination[preferencesMarker] = true
            defaults.setPersistentDomain(destination, forName: domain)
        }
        // History migration is independently retryable if access is temporarily denied.
        let target = home.appendingPathComponent(AppIdentity.historyPath)
        guard !FileManager.default.fileExists(atPath: target.path),
              safePath(target.deletingLastPathComponent(), home: home) else { return }
        for folder in retiredFolderNames {
            let source = home.appendingPathComponent("Library/Application Support/" + folder + "/history.json")
            guard safePath(source, home: home),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: source.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let size = attributes[.size] as? NSNumber, size.intValue <= 32 * 1024 * 1024,
                  let data = try? Data(contentsOf: source),
                  (try? JSONDecoder().decode([AuditEntry].self, from: data)) != nil else { continue }
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                // Never replace a file created concurrently, and never move the original.
                try data.write(to: target, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            } catch { }
            return
        }
    }

    private static func safePath(_ path: URL, home: URL) -> Bool {
        let root = home.standardizedFileURL.path
        let value = path.standardizedFileURL.path
        guard value.hasPrefix(root + "/") else { return false }
        var current = home
        for component in value.dropFirst(root.count + 1).split(separator: "/") {
            current.appendPathComponent(String(component))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink { return false }
        }
        return true
    }
}
