import Foundation
import Darwin
import AppKit

struct CleanTarget: Sendable {
    let url:URL; let category:String; let explanation:String
    var runningIDs:[String]=[]; var title:String?; var risk:String?; var readOnlyReason:String?
}
struct CleanDiscovery: Sendable {
    var targets:[CleanTarget]=[]; var issues:[String]=[]; var denied:[String]=[]
}
// Native, bounded adaptations of the pinned Bonsai clean/user, system, dev,
// app_caches and brew rules. Never enumerate synced documents as cache data.
enum ExpandedCleanCatalog {
    static func discover(home:URL,systemRoot:URL?) throws -> CleanDiscovery {
        var result=CleanDiscovery(); let end=ProcessInfo.processInfo.systemUptime+12
        func containedPath(_ url:URL) -> Bool {
            var ancestor=physicalURL(url)
            while ancestor.path != "/" {
                if let identity=try? Identity.read(ancestor),identity.isSymlink {return false}
                ancestor.deleteLastPathComponent()
            }
            return true
        }
        func list(_ url:URL) throws -> [URL] {
            try Task.checkCancellation()
            do {
                let id=try Identity.read(url)
                guard id.isDirectory,!id.isSymlink,containedPath(url) else {return []}
                let contents=try DirectoryListing.read(url,limit:1_000,expected:id,deadlineUptime:end)
                if !contents.complete {result.issues.append(url.path+": discovery limit reached.")}
                return contents.urls.sorted {$0.path<$1.path}
            } catch is CancellationError {throw CancellationError()}
            catch {if FileAccess.status(error) != .missing {result.issues.append(url.path+": "+error.localizedDescription);if FileAccess.isPermission(error) {result.denied.append(url.path)}};return []}
        }
        func add(_ url:URL,category:String,title:String?=nil,detail:String,risk:String?=nil,ids:[String]=[],readOnly:String?=nil) {
            guard containedPath(url),(try? Identity.read(url)) != nil else {return}
            result.targets.append(CleanTarget(url:url,category:category,explanation:detail,runningIDs:ids,title:title,risk:risk,readOnlyReason:readOnly))
        }
        for container in try list(home.appendingPathComponent("Library/Containers")) {
            let identifier=container.lastPathComponent
            guard !identifier.hasPrefix("."),let containerIdentity=try? Identity.read(container),containerIdentity.isDirectory,!containerIdentity.isSymlink,!AppIdentity.protectedNamePrefixes.contains(where:{identifier.hasPrefix($0)}),identifier.contains(".") else {continue}
            // Specific children of the generated-cache directory, never the
            // container root, Documents, preferences, databases or cookies.
            for child in try list(container.appendingPathComponent("Data/Library/Caches")) {
                let category=CleanCatalog.classify(identifier).0
                add(child,category:category,title:identifier+" · "+child.lastPathComponent,detail:"Generated container cache. Personal documents, settings and container databases are kept. Quit the related app before cleaning.",ids:[identifier])
            }
        }
        for account in try list(home.appendingPathComponent("Library/Caches/CloudKit/com.apple.bird")) {
            add(account.appendingPathComponent("Assets"),category:"Cloud clients",title:"iCloud Drive cache assets",detail:"Locally cached iCloud assets. Synced documents are kept; content may be downloaded again. Review offline needs.",risk:"High",ids:["com.apple.bird"])
        }
        // Only Assets is targeted; other CloudKit databases are kept.
        let updater=home.appendingPathComponent("Library/Application Support/Microsoft/EdgeUpdater/apps/msedge-stable")
        let staged=try list(updater).filter {url in
            guard url.lastPathComponent.range(of:"^[0-9]+(?:\\.[0-9]+){1,5}$",options:.regularExpression) != nil,let id=try? Identity.read(url) else {return false}
            return id.isDirectory && !id.isSymlink
        }
        let installedRoot=systemRoot ?? (physicalURL(home)==physicalURL(FileManager.default.homeDirectoryForCurrentUser) ? URL(fileURLWithPath:"/") : nil)
        let edgeLocations=[home.appendingPathComponent("Applications/Microsoft Edge.app")]+(installedRoot.map {[$0.appendingPathComponent("Applications/Microsoft Edge.app")]} ?? [])
        var installed:String?
        for app in edgeLocations {
            let plist=app.appendingPathComponent("Contents/Info.plist")
            guard containedPath(plist),let id=try? Identity.read(plist),!id.isSymlink,!id.isDirectory,id.size<=1_048_576,
                  let handle=try? FileHandle(forReadingFrom:plist) else {continue}
            defer {try? handle.close()}
            if let data=try? handle.read(upToCount:1_048_577),data.count<=1_048_576,
               let value=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
               let version=value["CFBundleShortVersionString"] as? String,
               version.range(of:"^[0-9]+(?:\\.[0-9]+){1,5}$",options:.regularExpression) != nil {installed=version;break}
        }
        let boundary=installed ?? (staged.count>1 ? staged.map(\.lastPathComponent).max(by:{$0.compare($1,options:.numeric) == .orderedAscending}) : nil)
        if let boundary {
            for version in staged where version.lastPathComponent.compare(boundary,options:.numeric) == .orderedAscending {
                add(version,category:"Browsers",title:"Edge updater old version · "+version.lastPathComponent,detail:"Old staged Edge installer payload. The installed version or newest staged payload is retained. Quit Edge and its updater before cleaning.",risk:"High",ids:["com.microsoft.edgemac","com.microsoft.EdgeUpdater"])
            }
        }
        for profile in try list(home.appendingPathComponent("Library/Application Support/Firefox/Profiles")) {
            add(profile.appendingPathComponent("cache2"),category:"Browsers",title:"Firefox · "+profile.lastPathComponent,detail:"Firefox generated profile cache. Passwords, cookies, bookmarks and session data are kept.",risk:"Review",ids:["org.mozilla.firefox"])
        }
        let cache=UserCacheLocation.url
        if physicalURL(home)==physicalURL(FileManager.default.homeDirectoryForCurrentUser),let cache {
            for child in try list(cache) where !AppIdentity.protectedNamePrefixes.contains(where:{child.lastPathComponent.hasPrefix($0)}) {
                let (_,ids)=CleanCatalog.classify(child.lastPathComponent)
                add(child,category:"Temporary files",title:"Temporary cache · "+child.lastPathComponent,detail:"User-specific generated cache in macOS’s temporary cache directory. Quit its app before cleanup.",risk:"High",ids:ids)
            }
        }
        let root=systemRoot ?? (physicalURL(home)==physicalURL(FileManager.default.homeDirectoryForCurrentUser) ? URL(fileURLWithPath:"/") : nil)
        if let root {
            for (path,title) in [("Library/Caches","System caches"),("Library/Logs/DiagnosticReports","Crash reports"),("private/var/log","System logs"),("private/var/db/DiagnosticPipeline","Diagnostic pipeline")] {
                // Each entry is inventory only. Never Trash the entire system
                // cache/log root or mutate active logs/databases.
                add(root.appendingPathComponent(path),category:"System Caches",title:title,detail:"macOS diagnostic or cache storage. Inventory only; system-managed contents may be active. Reveal in Finder to inspect.",risk:"High",readOnly:"System-managed location. Bonsai measures it but does not remove it or request a password.")
            }
            for package in try list(root.appendingPathComponent("opt/homebrew/Cellar")) {
                let activeLink=root.appendingPathComponent("opt/homebrew/opt/"+package.lastPathComponent)
                guard let link=try? FileManager.default.destinationOfSymbolicLink(atPath:activeLink.path) else {continue}
                let active=physicalURL(activeLink.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL)
                guard within(active.path,physicalURL(package).path),let activeID=try? Identity.read(active),activeID.isDirectory,!activeID.isSymlink else {continue}
                for version in try list(package) where version != active && version.lastPathComponent.compare(active.lastPathComponent,options:.numeric) == .orderedAscending {
                    add(version,category:"Developer artifacts",title:"Homebrew old version · "+package.lastPathComponent+" "+version.lastPathComponent,detail:"Older than the version referenced by Homebrew’s opt link. Homebrew must check dependency and retention rules; use brew cleanup --dry-run to review, then brew cleanup for supported removal.",risk:"High",readOnly:"Managed by Homebrew. Reveal this version; use Homebrew cleanup rather than deleting package files directly.")
                }
            }
        }
        if let root {
                for plist in try list(root.appendingPathComponent("Library/LaunchDaemons")) where plist.pathExtension=="plist" {
                    guard let metadata=try? Identity.read(plist),!metadata.isSymlink,!metadata.isDirectory,metadata.size<=65_536,
                          let handle=try? FileHandle(forReadingFrom:plist) else {continue}
                    defer {try? handle.close()}
                    guard let data=try? handle.read(upToCount:65_537),data.count<=65_536,
                          let value=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
                          let executable=(value["Program"] as? String) ?? (value["ProgramArguments"] as? [String])?.first,executable.hasPrefix("/") else {continue}
                    let target=root.appendingPathComponent(String(executable.dropFirst()))
                    do {_=try Identity.read(target)} catch {
                        guard FileAccess.status(error) == .missing else {continue}
                        add(plist,category:"System Caches",title:"Possible orphaned service · "+plist.deletingPathExtension().lastPathComponent,detail:"This launch daemon references a missing executable: "+executable+". A service may reinstall it later. Inspect the definition and remove through its app or administrator tools.",risk:"High",readOnly:"System launch service. Inventory only; Bonsai does not disable or delete it during cleaning.")
                    }
                }
                let soundApps=["com.apple.garageband10","com.apple.logic10"]
                let knownSoundApp = physicalURL(home)==physicalURL(FileManager.default.homeDirectoryForCurrentUser) && soundApps.contains {id in NSWorkspace.shared.urlForApplication(withBundleIdentifier:id).map {FileManager.default.fileExists(atPath:$0.path)} == true}
                if !knownSoundApp {
                    for path in ["Library/Application Support/Logic","Library/Audio/Apple Loops"] {
                        add(root.appendingPathComponent(path),category:"Potential app leftovers",title:"Apple Sound Library · "+URL(fileURLWithPath:path).lastPathComponent,detail:"Shared Apple instrument and loop content. Logic and GarageBand were not found through LaunchServices; other audio tools may still use it. Inventory only, never selected automatically.",risk:"High",readOnly:"Shared sound content may still be needed. Reveal in Finder; app absence does not establish that these samples are unused.")
                    }
                }
            }
        for child in try list(home.appendingPathComponent(".Trash")) {
            add(child,category:"Trash",title:child.lastPathComponent,detail:"Already in Trash. Permanently deleting this item cannot be undone. Review Trash separately; it is never selected with normal cleanup.",risk:"Permanent")
        }
        return result
    }
}

public enum ContainerCacheScope {
    public static func policy(for item:ReviewItem,base:PathPolicy,home:URL=FileManager.default.homeDirectoryForCurrentUser) throws -> PathPolicy {
        let containers=physicalURL(home.appendingPathComponent("Library/Containers"))
        guard within(item.id,containers.path) else {return base}
        let parts=Array(item.url.pathComponents.dropFirst(containers.pathComponents.count))
        guard parts.count>=5,parts[0].contains("."),Array(parts[1...3])==["Data","Library","Caches"],item.readOnlyReason==nil else {throw BonsaiError.refused("Only specific generated container caches may be cleaned.")}
        let scope=containers.appendingPathComponent(parts[0]+"/Data/Library/Caches")
        var cursor=scope
        while within(cursor.path,containers.path) {
            let id=try Identity.read(cursor)
            guard id.owner==base.uid,!id.isSymlink,id.isDirectory else {throw BonsaiError.refused("Container cache ancestry changed or belongs to another user.")}
            cursor.deleteLastPathComponent()
        }
        guard base.roots.contains(where:{within(scope.path,$0.path)}) else {throw BonsaiError.refused("Container is outside permitted locations.")}
        // Narrow this one item's policy to descendants of its generated-cache
        // root. Other protections, including user exclusions, remain effective.
        var protections=base.protected
        if let index=protections.firstIndex(where:{$0.path==containers.path}) {protections.remove(at:index)}
        return PathPolicy(roots:[scope],protected:protections,uid:base.uid)
    }
}
