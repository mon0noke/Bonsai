import Foundation
public enum MaintenanceCacheTrash {
    public static let names:Set<String>=["com.apple.QuickLook.thumbnailcache","com.apple.iconservices.store","com.apple.iconservices"]
    public static func move(_ url:URL,home:URL=FileManager.default.homeDirectoryForCurrentUser,runningIDs:Set<String>=[],exclusions:[String]=[],mover:@Sendable (URL) throws -> URL? = {try TrashService.systemTrash($0)}) throws -> URL? {
        let cache=home.appendingPathComponent("Library/Caches")
        let states=home.appendingPathComponent("Library/Saved Application State"),preferences=home.appendingPathComponent("Library/Preferences")
        let shared=home.appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        let isList=within(url.path,shared.path) && ["sfl2","sfl3"].contains(url.pathExtension) && !url.path.contains("ApplicationRecentDocuments")
        let isCache=url.deletingLastPathComponent()==cache && names.contains(url.lastPathComponent)
        let isState=url.deletingLastPathComponent()==states && url.pathExtension=="savedState"
        let isPreference=[preferences,preferences.appendingPathComponent("ByHost")].contains(url.deletingLastPathComponent()) && url.pathExtension=="plist" && !url.lastPathComponent.hasPrefix("com.apple.") && !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != "loginwindow.plist"
        guard isCache || isState || isPreference || isList else {throw BonsaiError.refused("This path is outside supported maintenance locations.")}
        let expected=try Identity.read(url)
        let policy=PathPolicy(roots:[cache,states,preferences,shared],protected:exclusions.map {URL(fileURLWithPath:$0)})
        try policy.validate(url,expected:expected)
        if !isCache {
            let identifier=url.deletingPathExtension().lastPathComponent
            guard !runningIDs.contains(where:{identifier==$0 || identifier.hasPrefix($0+".")}) else {throw BonsaiError.refused("Quit this application before repairing its files.")}
            if isState {guard expected.isDirectory,Date().timeIntervalSince1970-Double(expected.modified)>31*86400 else {throw BonsaiError.refused("Only saved states older than 30 days are eligible.")}}
            if isPreference || isList {
                guard !expected.isDirectory,expected.size<=16_777_216 else {throw BonsaiError.refused("Unsupported preference file.")}
                let data=try Data(contentsOf:url)
                guard (try? PropertyListSerialization.propertyList(from:data,format:nil))==nil else {throw BonsaiError.refused("This preference file is valid and will be kept.")}
            }
        }
        try policy.validate(url,expected:expected)
        let current=try FileScanner.measure(url,limits:ScanLimits(nodes:50_000,seconds:10))
        guard current.complete,!current.hasExternalLinks,current.manifest.allSatisfy({$0.value.owner==policy.uid && !$0.value.isSymlink}) else {throw BonsaiError.refused("Cache contains protected, linked, changed or unmeasured files.")}
        let parent=try Identity.read(url.deletingLastPathComponent())
        let verify=try FileScanner.measure(url,limits:ScanLimits(nodes:50_000,seconds:10))
        guard verify.complete,verify.manifest==current.manifest else {throw BonsaiError.changed("Cache changed during maintenance. Retry when Finder is idle.")}
        try Task.checkCancellation();try policy.validate(url,expected:expected)
        guard try Identity.read(url.deletingLastPathComponent()).sameObject(as:parent) else {throw BonsaiError.changed("Cache parent changed.")}
        let destination=try mover(url)
        guard (try? Identity.read(url)).map({!$0.sameObject(as:expected)}) ?? true else {throw BonsaiError.changed("Cache remains at its original path; retirement needs verification.")}
        return destination
    }
}
