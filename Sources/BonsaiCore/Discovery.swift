import Foundation
import AppKit

public enum InstalledIdentifiers {
    public static var roots: [URL] { let h=FileManager.default.homeDirectoryForCurrentUser; return [URL(fileURLWithPath:"/Applications"),URL(fileURLWithPath:"/System/Applications"),h.appendingPathComponent("Applications"),h.appendingPathComponent("Library/Application Support/Setapp/Applications")] }
    public struct Snapshot:Sendable {
        public let identifiers:Set<String>;public let issues:[String];public let blockedPaths:[String]
        public var complete:Bool {issues.isEmpty}
    }
    // Ordinary metadata only. A denied branch must not abort useful cache scans
    // or be mistaken for evidence that every unlisted app is absent.
    public static func snapshot(roots:[URL]=InstalledIdentifiers.roots,limits:ScanLimits=ScanLimits(nodes:20_000,seconds:8)) throws -> Snapshot {
        var queue=roots.map {($0,0)};var result=Set<String>();var issues:[String]=[];var denied:[String]=[]
        var visited=Set<String>();var nodes=0;let end=ProcessInfo.processInfo.systemUptime+limits.seconds
        while let (url,depth)=queue.popLast() {
            try Task.checkCancellation()
            guard visited.insert(url.standardizedFileURL.path).inserted else {continue}
            nodes += 1
            guard nodes<=limits.nodes,ProcessInfo.processInfo.systemUptime<end else {issues.append("Application inventory reached its scan limit.");break}
            do {
                let identity=try Identity.read(url);guard identity.isDirectory,!identity.isSymlink else {continue}
                if url.pathExtension.lowercased()=="app" {
                    let info=url.appendingPathComponent("Contents/Info.plist")
                    let metadata=try Identity.read(info)
                    guard !metadata.isSymlink,!metadata.isDirectory,metadata.size<=1_048_576 else {issues.append("App identifier metadata is unsupported: "+url.path);continue}
                    let handle=try FileHandle(forReadingFrom:info);defer {try? handle.close()}
                    let data=try handle.read(upToCount:1_048_577) ?? Data()
                    guard data.count<=1_048_576,let value=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],let name=value["CFBundleIdentifier"] as? String,!name.isEmpty else {issues.append("An app bundle has no readable identifier: "+url.path);continue}
                    result.insert(name)
                } else if depth<3 {
                    let contents=try DirectoryListing.read(url,limit:max(0,limits.nodes-nodes-queue.count),expected:identity,deadlineUptime:end)
                    if !contents.complete {issues.append("Application folder enumeration is incomplete: "+url.path)}
                    queue += contents.urls.map {($0,depth+1)}
                }
            } catch is CancellationError {throw CancellationError()}
            catch {
                if FileAccess.status(error) == .missing && url.pathExtension.lowercased() != "app" {continue}
                issues.append("Skipped application folder: "+url.path)
                if FileAccess.isPermission(error) {denied.append(url.path)}
            }
        }
        return Snapshot(identifiers:result,issues:issues,blockedPaths:Array(Set(denied)).sorted())
    }
    public static func read(roots:[URL]=InstalledIdentifiers.roots) throws -> Set<String> {
        let value=try snapshot(roots:roots)
        guard value.complete else {throw BonsaiError.unavailable("Installed-app discovery is incomplete. Unverified leftovers are left untouched; other cleanup can continue. "+value.issues.prefix(3).joined(separator:"; "))}
        return value.identifiers
    }
    public static func claims(_ candidate: String, installed: Set<String>) -> Bool {
        installed.contains { $0==candidate || $0.hasPrefix(candidate+".") || candidate.hasPrefix($0+".") }
    }
    public static func verifyAbsent(_ identifier: String) throws {
        // Explicit, high-risk review permits a candidate even when unrelated inventory
        // branches are inaccessible. Known installed claims and LaunchServices still veto it.
        try verifyAbsent(identifier,installed:snapshot().identifiers)
    }
    public static func verifyAbsent(_ identifier:String,installed:Set<String>) throws {
        guard !claims(identifier,installed:installed) else { throw BonsaiError.changed("An installed application now claims this identifier. Refresh the remnant scan.") }
        if let location=NSWorkspace.shared.urlForApplication(withBundleIdentifier:identifier),FileManager.default.fileExists(atPath:location.path) { throw BonsaiError.refused("LaunchServices still knows an installed application for this identifier. Reveal and inspect the item manually.") }
    }
    public static func parseAuthorized(_ data:Data,roots:[URL]=InstalledIdentifiers.roots,reader:(URL)throws->String?={url in
        let file=url.appendingPathComponent("Contents/Info.plist")
        let data:Data
        do {data=try Data(contentsOf:file)} catch {if FileAccess.status(error) == .missing {return nil};throw error}
        let value=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
        return value?["CFBundleIdentifier"] as? String
    }) throws -> Set<String> {
        guard data.count<=1_048_576,data.last==0 else {throw BonsaiError.unavailable("App discovery returned incomplete output. Retry the read-only scan.")}
        let records=data.split(separator:0).map {String(data:$0,encoding:.utf8)}
        guard records.allSatisfy({$0 != nil}),records.last.flatMap({$0}) == "BONSAI_FIND_STATUS:0" else {throw BonsaiError.unavailable("App discovery could not inspect every folder. No leftovers are offered from an incomplete inventory.")}
        var identifiers=Set<String>()
        for path in records.dropLast().compactMap({$0}) {
            try Task.checkCancellation()
            let url=URL(fileURLWithPath:path)
            guard path.hasPrefix("/"),!path.components(separatedBy:"/").contains(".."),url.path==path,url.pathExtension.lowercased()=="app",
                  roots.contains(where:{root in within(path,root.path) && url.pathComponents.count-root.pathComponents.count<=3}) else {
                throw BonsaiError.refused("App discovery returned a path outside its approved roots.")
            }
            if let value=try reader(url),!value.isEmpty {identifiers.insert(value)}
        }
        return identifiers
    }

}
public enum RemnantScanner {
    public static func identifier(_ leaf: String) -> String? {
        var value=leaf
        for suffix in [".plist",".savedState"] where value.hasSuffix(suffix) { value=String(value.dropLast(suffix.count)) }
        guard value.range(of:"^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9_-]+){2,}$",options:.regularExpression) != nil,
              !value.hasPrefix("com.apple."),!AppIdentity.protectedNamePrefixes.contains(where:{value.hasPrefix($0)}),!value.hasPrefix("group.") else { return nil }
        return value
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, installed: Set<String>, exclusions: [String] = [], inventoryComplete:Bool=true, progress: @Sendable (String,Int) -> Void = { _,_ in }) throws -> CleanReport {
        var items:[ReviewItem]=[]; var issues:[String]=[];var denied:[String]=[]; var nodes=0; let deadline=ProcessInfo.processInfo.systemUptime+45
        for directory in ["Library/Caches","Library/Preferences","Library/Saved Application State","Library/HTTPStorages","Library/WebKit","Library/Application Support"] {
            let root=home.appendingPathComponent(directory); guard FileManager.default.fileExists(atPath:root.path) else { continue }
            do {
                for url in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) {
                    try Task.checkCancellation()
                    guard ProcessInfo.processInfo.systemUptime<deadline,nodes<100_000 else { issues.append("Remnant scan budget reached. Results are partial."); return CleanReport(items:items,issues:issues,completeWithinCatalog:false,deniedDiscoveryPaths:denied) }
                    guard let identifier=identifier(url.lastPathComponent),!InstalledIdentifiers.claims(identifier,installed:installed),!exclusions.contains(where:{within(physicalURL(url).path,physicalURL(URL(fileURLWithPath:$0)).path)}) else { continue }
                    let id=try Identity.read(url); guard id.owner==getuid(),!id.isSymlink else { continue }
                    if home==FileManager.default.homeDirectoryForCurrentUser,let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:identifier),FileManager.default.fileExists(atPath:app.path) { continue }
                    let measurement=try FileScanner.measure(url,limits:ScanLimits(nodes:min(30_000,100_000-nodes),seconds:5)); nodes += measurement.manifest.count
                    denied += measurement.accessDeniedPaths ?? []
                    guard measurement.files>0 else { continue }
                    items.append(try ReviewItem(url:url,title:identifier,category:"Potential app leftovers",explanation:"Exact identifier path with no matching app in the inspected inventory. This is evidence, not proof of abandonment. May contain settings or personal data; check each path. "+(inventoryComplete ? "" : "Some application folders could not be inspected. An app outside the inspected inventory may still use these files. ")+"Known application claims are checked again before cleanup.",risk:"High",confidence:inventoryComplete ? "Identifier absent from inventory" : "Possible leftover · inventory incomplete",runningIDs:[identifier],measurement:measurement,absentBundleID:identifier))
                    progress(identifier,items.count)
                }
            } catch is CancellationError { throw CancellationError() } catch { issues.append(root.lastPathComponent+": "+error.localizedDescription);if let path=FileAccess.deniedURL(error,fallback:root) {denied.append(path.path)} }
        }
        return CleanReport(items:items,issues:issues,completeWithinCatalog:issues.isEmpty && items.allSatisfy { $0.measurement.complete },deniedDiscoveryPaths:denied)
    }
}
public enum InstallerScanner {
    public static func scan(_ root:URL,now:Date=Date(),exclusions:[String]=[],limits:ScanLimits=ScanLimits(nodes:10_000,seconds:20)) throws -> CleanReport {
        try Task.checkCancellation()
        let deadline=ProcessInfo.processInfo.systemUptime+limits.seconds
        let contents=try DirectoryListing.read(root,limit:min(1_000,limits.nodes),expected:Identity.read(root),deadlineUptime:deadline)
        var items:[ReviewItem]=[];var issues:[String]=[];var denied:[String]=[];var nodes=contents.urls.count
        if !contents.complete {issues.append("Installer enumeration reached its limit; unvisited entries are omitted.")}
        for url in contents.urls {
            try Task.checkCancellation()
            guard nodes<limits.nodes,ProcessInfo.processInfo.systemUptime<deadline else {issues.append("Installer phase reached its time or node limit.");break}
            guard ["dmg","pkg","xip","iso"].contains(url.pathExtension.lowercased()),!exclusions.contains(where:{within(physicalURL(url).path,physicalURL(URL(fileURLWithPath:$0)).path)}) else {continue}
            do {
                let id=try Identity.read(url);guard !id.isDirectory,!id.isSymlink,id.owner==getuid(),now.timeIntervalSince1970-Double(id.modified)>7*86400 else {continue}
                let measured=try FileScanner.measure(url,limits:ScanLimits(nodes:max(1,limits.nodes-nodes),seconds:min(5,max(0,deadline-ProcessInfo.processInfo.systemUptime))))
                nodes += measured.manifest.count
                items.append(try ReviewItem(url:url,title:url.lastPathComponent,category:"Old installers",explanation:"Installer or disk image untouched for at least seven days. Keep anything needed for reinstalls or rollback. Eject mounted images and finish installations before moving it to Trash.",risk:"High",confidence:"Extension and age; manual review",measurement:measured))
            } catch is CancellationError {throw CancellationError()}
            catch {issues.append(url.lastPathComponent+": "+error.localizedDescription);if let path=FileAccess.deniedURL(error,fallback:url) {denied.append(path.path)}}
        }
        return CleanReport(items:items,issues:issues,completeWithinCatalog:contents.complete && issues.isEmpty && items.allSatisfy {$0.measurement.complete},deniedDiscoveryPaths:denied)
    }

}
public struct TrashAppNotice: Identifiable, Sendable { public let id:String; public let name:String; public let url:URL }
public enum TrashAppMonitor {
    public static func inspect(_ root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) throws -> [TrashAppNotice] {
        var result:[TrashAppNotice]=[]
        for url in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).prefix(500) where url.pathExtension.lowercased()=="app" {
            try Task.checkCancellation(); let identity=try Identity.read(url); guard identity.isDirectory,!identity.isSymlink,identity.owner==getuid(),let b=Bundle(url:url),let id=b.bundleIdentifier else { continue }
            result.append(TrashAppNotice(id:id,name:b.infoDictionary?["CFBundleDisplayName"] as? String ?? url.deletingPathExtension().lastPathComponent,url:url))
        }
        return result.sorted { $0.name<$1.name }
    }
}

public enum ApplicationActivity {
    public static func isRunning(_ patterns:[String],among identifiers:Set<String>) -> Bool {
        patterns.contains { pattern in
            if pattern.hasSuffix(".*") { let prefix=String(pattern.dropLast());return identifiers.contains { $0.hasPrefix(prefix) } }
            return identifiers.contains(pattern)
        }
    }
}
