import Foundation

public enum AppIdentity {
    public static let bundleIdentifier = "app.bonsai.mac"
    public static let protectedNamePrefixes = ["app.bonsai."] + BrandingMigration.retiredPrefixes
    public static let protectedFolderNames = ["Bonsai"] + BrandingMigration.retiredFolderNames
    public static let historyPath = "Library/Application Support/Bonsai/history.json"
    public static let diskCachePath = "Library/Caches/app.bonsai.mac/Analyze"
}
