import Foundation
import AppKit
import ServiceManagement
import CoreServices

public struct InstalledApp: Identifiable, Sendable {
    public var id: String { url.path }; public let url: URL; public let name: String; public let bundleID: String
    public let version: String; public let measurement: Measurement; public let lastUsed: Date?; public let appStore: Bool
    public let lastUsedSource:String; public let installedDate:Date?;public let isMenuBarApp:Bool
    public init(url:URL,name:String,bundleID:String,version:String,measurement:Measurement,lastUsed:Date?,appStore:Bool,lastUsedSource:String="Filesystem access",installedDate:Date?=nil,isMenuBarApp:Bool=false) { self.url=url;self.name=name;self.bundleID=bundleID;self.version=version;self.measurement=measurement;self.lastUsed=lastUsed;self.appStore=appStore;self.lastUsedSource=lastUsedSource;self.installedDate=installedDate;self.isMenuBarApp=isMenuBarApp }
}
public struct AppInventoryReport: Sendable {
    public let apps:[InstalledApp]; public let complete:Bool; public let issues:[String]
}
public enum AppInventory {
    public static func refreshed(_ app:InstalledApp) throws -> InstalledApp {
        let file=app.url.appendingPathComponent("Contents/Info.plist"),id=try Identity.read(file)
        guard !id.isSymlink,!id.isDirectory,id.size<=1_048_576 else {throw BonsaiError.changed("Application metadata changed.")}
        let info=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),format:nil) as? [String:Any]
        guard info?["CFBundleIdentifier"] as? String==app.bundleID,let version=info?["CFBundleShortVersionString"] as? String ?? info?["CFBundleVersion"] as? String else {throw BonsaiError.changed("Updated application identity is unavailable.")}
        let measurement=try FileScanner.measure(app.url,limits:ScanLimits(nodes:100_000,seconds:3))
        return InstalledApp(url:app.url,name:app.name,bundleID:app.bundleID,version:version,measurement:measurement,lastUsed:app.lastUsed,appStore:app.appStore,lastUsedSource:app.lastUsedSource,installedDate:app.installedDate,isMenuBarApp:app.isMenuBarApp)
    }

    public static func scan(roots:[URL]?=nil,measureSizes:Bool=true,progress:@Sendable (InstalledApp,Int)->Void={_,_ in}) throws -> [InstalledApp] {
        try inspect(roots:roots,measureSizes:measureSizes,progress:progress).apps
    }
    public static func inspect(roots:[URL]?=nil,measureSizes:Bool=true,limits:ScanLimits=ScanLimits(nodes:20_000,seconds:90),progress:@Sendable (InstalledApp,Int)->Void={_,_ in}) throws -> AppInventoryReport {
        var queue=(roots ?? InstalledIdentifiers.roots).map { ($0,0) }
        var visited=Set<String>();var result:[InstalledApp]=[];var issues:[String]=[];var nodes=0;let deadline=ProcessInfo.processInfo.systemUptime+limits.seconds
        while let (url,depth)=queue.popLast() {
            try Task.checkCancellation();nodes += 1
            guard nodes<=limits.nodes,ProcessInfo.processInfo.systemUptime<deadline else { issues.append("Inventory budget reached; remaining locations were not inspected. Refresh or add a specific app.");break }
            guard visited.insert(physicalURL(url).path).inserted,FileManager.default.fileExists(atPath:url.path) else { continue }
            do {
                let id=try Identity.read(url);guard id.isDirectory,!id.isSymlink else { continue }
                if url.pathExtension.lowercased()=="app" {
                    guard let bundle=Bundle(url:url) else { issues.append("Unreadable bundle: "+url.lastPathComponent);continue }
                    let info=bundle.infoDictionary ?? [:];var used:Date?;var source="Unavailable"
                    if let metadata=MDItemCreate(kCFAllocatorDefault,url.path as CFString),let date=MDItemCopyAttribute(metadata,kMDItemLastUsedDate) as? Date { used=date;source="Spotlight last used" }
                    let activity=AppActivity.inspect(bundleID:bundle.bundleIdentifier ?? "",name:info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,opened:used)
                    used=activity.date;source=activity.source
                    var m=measureSizes ? try FileScanner.measure(url,limits:ScanLimits(nodes:30_000,seconds:min(3,max(0,deadline-ProcessInfo.processInfo.systemUptime)))) : Measurement();m.manifest=[physicalURL(url).path:id]
                    let added=(try? url.resourceValues(forKeys:[.creationDateKey]))?.creationDate
                    let app=InstalledApp(url:physicalURL(url),name:info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,bundleID:bundle.bundleIdentifier ?? "",version:info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "Unknown",measurement:m,lastUsed:used,appStore:FileManager.default.fileExists(atPath:url.appendingPathComponent("Contents/_MASReceipt/receipt").path),lastUsedSource:source,installedDate:added,isMenuBarApp:AppActivity.menuBarAgent(info["LSUIElement"]))
                    result.append(app);progress(app,result.count)
                } else if depth<3 { queue += try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).map { ($0,depth+1) } }
            } catch is CancellationError { throw CancellationError() } catch { issues.append(url.lastPathComponent+": "+error.localizedDescription) }
        }
        return AppInventoryReport(apps:result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },complete:issues.isEmpty,issues:issues)
    }
    public static func associated(_ app:InstalledApp,inventory:[InstalledApp],home:URL=FileManager.default.homeDirectoryForCurrentUser) throws -> [ReviewItem] {
        try associationReport(app,inventory:inventory,home:home).files.map(\.item)
    }
    /// Bounded read-only discovery. Each candidate keeps its own access/scan result.
    public static func associationReport(_ app:InstalledApp,inventory:[InstalledApp],home:URL=FileManager.default.homeDirectoryForCurrentUser,temporaryCacheRoot:URL?=UserCacheLocation.url,systemLibrary:URL=URL(fileURLWithPath:"/Library"),policy:PathPolicy = .standard,limits:ScanLimits=ScanLimits(nodes:150_000,seconds:30)) throws -> AppAssociationReport {
        var files:[AppAssociatedFile]=[],issues:[String]=[];var seen=Set<String>();var nodes=0
        let deadline=ProcessInfo.processInfo.systemUptime+limits.seconds
        func add(_ url:URL,_ kind:AppFileKind,_ explanation:String,_ confidence:String="Exact bundle identifier") throws {
            try Task.checkCancellation();let url=physicalURL(url)
            guard FileManager.default.fileExists(atPath:url.path),seen.insert(url.path).inserted else { return }
            guard nodes<limits.nodes,ProcessInfo.processInfo.systemUptime<deadline else { issues.append("Discovery limit reached: "+url.lastPathComponent+" was not inspected. Refresh or inspect in Finder.");return }
            let measurement=try FileScanner.measure(url,limits:ScanLimits(nodes:min(50_000,limits.nodes-nodes),seconds:min(8,max(0,deadline-ProcessInfo.processInfo.systemUptime))))
            nodes += measurement.manifest.count
            do {
                let item=try ReviewItem(url:url,title:kind == .application ? app.name : kind.rawValue,category:kind == .application ? "Application" : "Associated data",explanation:explanation,risk:kind.ready && kind != .application ? "Review" : "High",confidence:confidence,runningIDs:app.bundleID.isEmpty ? [] : [app.bundleID],measurement:measurement)
                var blocked:String?
                if !measurement.complete { blocked="Incomplete measurement. Resolve access or refresh." }
                else if measurement.manifest.values.contains(where:{$0.owner != policy.uid}) { blocked="Contains files owned by another user. Manage in Finder." }
                else { do { try policy.validate(url,expected:measurement.manifest[item.id]) } catch { blocked=error.localizedDescription } }
                files.append(AppAssociatedFile(item:item,kind:kind,blockedReason:blocked))
            } catch { issues.append(url.lastPathComponent+": "+error.localizedDescription) }
        }
        guard FileManager.default.fileExists(atPath:app.id) else { throw BonsaiError.changed("Application disappeared. Refresh the inventory before trying again.") }
        try add(app.url,.application,"The application bundle. Quit it before moving it to Trash.","Application bundle")
        guard !app.bundleID.isEmpty,app.bundleID.range(of:"^[A-Za-z0-9][A-Za-z0-9.-]+$",options:.regularExpression) != nil else { return AppAssociationReport(appID:app.id,files:files,issues:issues+["No usable bundle identifier; associated data was not inferred."]) }
        guard !inventory.contains(where:{$0.bundleID==app.bundleID && $0.id != app.id}) else { return AppAssociationReport(appID:app.id,files:files,issues:issues+["Another installed copy uses this bundle identifier. Shared data is retained."]) }
        let id=app.bundleID
        for (relative,kind,explanation) in [
            ("Library/Caches/\(id)",AppFileKind.cache,"Generated cache. Offline data may need downloading again."),
            ("Library/Logs/\(id)",.logs,"App-generated diagnostic logs. Export any logs you want to keep before removing."),
            ("Library/Preferences/\(id).plist",.preferences,"Preferences and settings will be reset. Review before selecting."),
            ("Library/Saved Application State/\(id).savedState",.savedState,"Saved windows and document state. Review before selecting."),
            ("Library/Application Support/\(id)",.support,"May contain personal documents, databases or downloads. Never selected by default."),
            ("Library/HTTPStorages/\(id)",.http,"May contain cookies and session data. Review before selecting."),
            ("Library/WebKit/\(id)",.webKit,"May contain website sessions and offline data. Review before selecting.")
        ] { try add(home.appendingPathComponent(relative),kind,explanation) }
        if let temporaryCacheRoot { try add(temporaryCacheRoot.appendingPathComponent(id),.temporaryCache,"Generated per-user temporary cache. The app recreates it when needed.") } else { issues.append("Per-user temporary cache location unavailable. That location was not inspected.") }
        // Name matches are explicitly tentative, unique in this inventory, and never defaults.
        let forbidden=["apple","google","microsoft","adobe","library","caches","application support","containers","group containers","cloudstorage","icloud"]+AppIdentity.protectedFolderNames.map {$0.lowercased()}
        let name=app.name
        if name.count>=3,name.count<=100,!name.contains("/"),name != ".",name != "..",!forbidden.contains(name.lowercased()),!inventory.contains(where:{$0.id != app.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame}) {
            try add(home.appendingPathComponent("Library/Application Support").appendingPathComponent(name),.support,"Possible app-name match. Ownership by this application is not proven; inspect contents before selecting.","App name match; manual review")
        }
        // Privileged helpers are discovered only from declarations in the app's own metadata.
        let declared=(Bundle(url:app.url)?.infoDictionary?["SMPrivilegedExecutables"] as? [String:String]) ?? [:]
        for label in Array(declared.keys).sorted().prefix(20) where label.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]+$",options:.regularExpression) != nil {
            try add(systemLibrary.appendingPathComponent("PrivilegedHelperTools/"+label),.helper,"Declared privileged helper. Bonsai does not elevate removal; use the vendor uninstaller or Finder.","Declared by application")
            try add(systemLibrary.appendingPathComponent("LaunchDaemons/"+label+".plist"),.launch,"Declared helper's launch item. Removing a plist does not stop an already-loaded service. Use the vendor uninstaller.","Declared helper identifier")
        }
        for base in [home.appendingPathComponent("Library/LaunchAgents"),systemLibrary.appendingPathComponent("LaunchAgents"),systemLibrary.appendingPathComponent("LaunchDaemons")] {
            try add(base.appendingPathComponent(id+".plist"),.launch,"Launch item with the exact bundle identifier. Disable the service through Startup or use the vendor uninstaller before removing its file.")
        }
        return AppAssociationReport(appID:app.id,files:files,issues:issues)
    }

}
public struct SoftwareUpdate: Identifiable, Sendable, Codable {
    public let id: String; public let name: String; public let installed: String; public let available: String; public let source: String; public let information: String
    public let applicationURL:URL?; public let sourceURL:URL?; public let releaseNotesURL:URL?
    public let downloadURL:URL?;public let downloadSHA512:String?;public let downloadSHA256:String?
    public let downloadSignature:String?;public let downloadBytes:UInt64?;public let availableBuild:String?
    public var sourceLabel:String {source=="Appcast" ? "Sparkle" : source.hasPrefix("Homebrew") ? "Homebrew" : source}
    public var usesSparkle:Bool {source=="Sparkle" || source=="Appcast"}
    public static var sparkleInstallationAvailable:Bool {
#if BONSAI_DIRECT_SPARKLE
 true
#else
 false
#endif
 }
    public var usesDirectArchive:Bool {(source=="Electron" && downloadSHA512 != nil || usesSparkle || ["Website","Homebrew catalog"].contains(source) && downloadSHA256 != nil) && downloadURL.map {PublicMetadataHTTP.valid($0) && ["zip","dmg"].contains($0.pathExtension.lowercased())}==true && applicationURL != nil}
    public var canPrepareInstaller:Bool {source=="Homebrew package" && downloadSHA256 != nil && downloadURL.map {PublicMetadataHTTP.valid($0) && $0.pathExtension.lowercased()=="pkg"}==true}
    public var canInstall:Bool { source=="Homebrew cask" || (usesSparkle && Self.sparkleInstallationAvailable) || source=="App Store" || usesDirectArchive }
    public init(id:String,name:String,installed:String,available:String,source:String,information:String,applicationURL:URL?=nil,sourceURL:URL?=nil,releaseNotesURL:URL?=nil,downloadURL:URL?=nil,downloadSHA512:String?=nil,downloadSHA256:String?=nil,downloadSignature:String?=nil,downloadBytes:UInt64?=nil,availableBuild:String?=nil) { self.downloadSHA256=downloadSHA256;self.downloadSignature=downloadSignature;self.downloadBytes=downloadBytes;self.availableBuild=availableBuild;self.downloadURL=downloadURL;self.downloadSHA512=downloadSHA512;self.id=id; self.name=name; self.installed=installed; self.available=available; self.source=source; self.information=information; self.applicationURL=applicationURL; self.sourceURL=sourceURL; self.releaseNotesURL=releaseNotesURL }
}
public enum UpdateService {
    public static var brewPath: String? { ["/opt/homebrew/bin/brew","/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath:$0) } }
    public static func parseBrew(_ data: Data) throws -> [SoftwareUpdate] {
        guard let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],let casks=json["casks"] as? [[String:Any]] else { throw BonsaiError.unavailable("Homebrew returned an unsupported response. No update availability can be inferred.") }
        return casks.compactMap { cask in
            guard let token = cask["name"] as? String ?? cask["token"] as? String, token.range(of:"^[a-z0-9][a-z0-9+@._-]*$",options:.regularExpression) != nil else { return nil }
            return SoftwareUpdate(id:token,name:token,installed:(cask["installed_versions"] as? [String])?.joined(separator:", ") ?? "Unknown",available:cask["current_version"] as? String ?? "Unknown",source:"Homebrew cask",information:"Homebrew catalog version. Open the source page for package details; upstream release notes are not provided by this response.")
        }
    }
    public static func check(consent: Bool, refreshCatalog: Bool = true) async throws -> ([SoftwareUpdate],String) {
        guard consent else { throw BonsaiError.refused("Network consent is required to contact update sources.") }
        var updates: [SoftwareUpdate] = []; var notes: [String] = []
        if let brew = brewPath {
            if refreshCatalog { let refresh = try await CommandRunner.run(brew,["update"],timeout:120); if !refresh.succeeded { notes.append("Homebrew refresh failed: \(refresh.output). Results use cached catalog.") } }
            try Task.checkCancellation()
            let result = try await CommandRunner.run(brew,["outdated","--cask","--json=v2"],timeout:60)
            if result.succeeded || result.status == 1 { if let data = result.standardOutput.data(using:.utf8) { updates = try parseBrew(data) } } else { notes.append("Homebrew check failed: \(result.output)") }
        } else { notes.append("Homebrew is not installed. Install it separately to manage cask updates.") }
        notes.append("App Store and macOS updates are handed off to their native applications. Other apps use their own updater. No unsupported version comparison is inferred.")
        return (updates,notes.joined(separator:"\n"))
    }
    public static func catalog(apps:[InstalledApp]) async throws -> ([SoftwareUpdate],String) {
        guard let brew=brewPath else {return ([],"Homebrew is not installed.")}
        let refresh=try await CommandRunner.run(brew,["update"],timeout:120)
        try Task.checkCancellation()
        let result=try await CommandRunner.runBrewCatalog(brew)
        guard result.succeeded else {return ([],"Homebrew could not read its installed catalog: "+result.standardError)}
        let prefix=URL(fileURLWithPath:brew).deletingLastPathComponent().deletingLastPathComponent()
        let taps=BrewCatalog.localTapReleases(root:prefix.appendingPathComponent("Library/Taps"))
        let items=try BrewCatalog.updates(Data(result.standardOutput.utf8),apps:apps,taps:taps)
        return (items,refresh.succeeded ? "Homebrew installed casks checked, including self-updating casks." : "Homebrew refresh failed; installed casks checked using cached metadata. "+refresh.standardError)
    }
    public static func install(_ item: SoftwareUpdate, consent: Bool,progress:@escaping SoftwareUpdateProgressHandler={_ in}) async -> ItemOutcome {
        if item.usesDirectArchive {return await DirectUpdates.install(item,consent:consent,progress:progress)}
        if item.source=="App Store" {return await StoreUpdates.install(item,consent:consent,progress:progress)}
        guard consent,item.source=="Homebrew cask",item.id.range(of:"^[a-z0-9][a-z0-9+@._-]*$",options:.regularExpression) != nil,let brew = brewPath else { return ItemOutcome(title:item.name,path:item.id,status:"Unavailable",detail:"Network consent and Homebrew are required.") }
        do {
            progress(SoftwareUpdateProgress(.installing))
            let result = try await CommandRunner.run(brew,["upgrade","--cask",item.id],timeout:300)
            guard result.succeeded else { return ItemOutcome(title:item.name,path:item.id,status:result.cancelled ? "Cancelled" : result.timedOut ? "Timed out" : "Failed",detail:result.output+"\nInstaller subprocesses already started may finish independently; check the app version before retrying.") }
            try Task.checkCancellation()
            progress(SoftwareUpdateProgress(.checking))
            let check = try await CommandRunner.run(brew,["outdated","--cask","--json=v2",item.id],timeout:30)
            guard check.succeeded || check.status==1 else { return ItemOutcome(title:item.name,path:item.id,status:"Check required",detail:result.output+"\nInstallation finished, but version verification failed:\n"+check.output) }
            let remaining = try parseBrew(Data(check.standardOutput.utf8))
            return ItemOutcome(title:item.name,path:item.id,status:result.succeeded && remaining.isEmpty ? "Updated" : "Check required",detail:result.output + "\nPost-check:\n" + check.output)
        } catch { return ItemOutcome(title:item.name,path:item.id,status:"Failed",detail:error.localizedDescription) }
    }
}
public struct StartupItem: Identifiable, Sendable {
    public var id: String { url.path }; public let url: URL; public let label: String; public let owner: UInt32
    public let source: String; public let loaded: Bool?; public let disabled: Bool?; public let command: String; public let identity: Identity; public let applicationURL:URL?; public let isProtected:Bool
    public init(url: URL, label: String, owner: UInt32, source: String, loaded: Bool?, disabled: Bool?, command: String, identity: Identity, applicationURL:URL?=nil,isProtected:Bool=false) {
        self.url=url; self.label=label; self.owner=owner; self.source=source; self.loaded=loaded; self.disabled=disabled; self.command=command; self.identity=identity;self.applicationURL=applicationURL;self.isProtected=isProtected
    }
    public var controllable: Bool { owner == getuid() && source == "User LaunchAgent" && disabled != nil && !isProtected }
    public var state: String {
        if disabled == true { return loaded == true ? "Disabled · still loaded" : "Disabled" }
        if loaded == true { return "Loaded" }
        if disabled == false && loaded == false { return "Enabled · not loaded" }
        return loaded == false ? "Not loaded · persistent state unavailable" : "State unavailable"
    }
}
public enum StartupService {
    public static func restorationCommands(_ item: StartupItem) -> [[String]] {
        let domain="gui/\(item.owner)"; let target=domain+"/"+item.label
        var commands=[[item.disabled == true ? "disable" : "enable",target]]
        if let loaded=item.loaded { commands.append(loaded ? ["bootstrap",domain,item.url.path] : ["bootout",target]) }
        return commands
    }
    public static func parseDisabled(_ output: String, label: String) -> Bool? {
        let escaped = NSRegularExpression.escapedPattern(for:label)
        guard let regex = try? NSRegularExpression(pattern:"\""+escaped+"\"\\s*=>\\s*(true|false)"),let m = regex.firstMatch(in:output,range:NSRange(output.startIndex...,in:output)),let range = Range(m.range(at:1),in:output) else { return output.contains("disabled services") ? false : nil }
        return output[range] == "true"
    }
    public static func inventory() async throws -> [StartupItem] {
        let domain = "gui/\(getuid())"; let disabled = try await CommandRunner.run("/bin/launchctl",["print-disabled",domain],timeout:10)
        let loaded = try await CommandRunner.run("/bin/launchctl",["list"],timeout:10)
        let systemDisabled = try await CommandRunner.run("/bin/launchctl",["print-disabled","system"],timeout:10)
        let deadline = Date().addingTimeInterval(30)
        let loadedLabels = Set(loaded.output.split(separator:"\n").compactMap { line -> String? in let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }); return parts.count >= 3 ? String(parts[2]) : nil })
        var result: [StartupItem] = []
        let paths = [(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),"User LaunchAgent"),(URL(fileURLWithPath:"/Library/LaunchAgents"),"System LaunchAgent"),(URL(fileURLWithPath:"/Library/LaunchDaemons"),"System LaunchDaemon")]
        for (root,source) in paths { for url in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "plist" {
            try Task.checkCancellation(); if Date() > deadline { break }
            guard let identity = try? Identity.read(url),!identity.isSymlink,let data = try? Data(contentsOf:url),let plist = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],let label = plist["Label"] as? String else { continue }
            guard label.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]+$",options:.regularExpression) != nil else { continue }
            var loadedState: Bool? = loaded.succeeded ? loadedLabels.contains(label) : nil
            let disabledResult = source == "System LaunchDaemon" ? systemDisabled : disabled
            if source == "System LaunchDaemon" {
                let probe = try await CommandRunner.run("/bin/launchctl",["print","system/"+label],timeout:2)
                loadedState = probe.succeeded ? true : probe.output.contains("Could not find service") ? false : nil
            }
            let command = (plist["ProgramArguments"] as? [String])?.joined(separator:" ") ?? plist["Program"] as? String ?? "Program not specified"
            let program=(plist["ProgramArguments"] as? [String])?.first ?? plist["Program"] as? String
            let appURL=program.flatMap {value -> URL? in guard value.hasPrefix("/"),let range=value.range(of:".app/") else {return nil};return URL(fileURLWithPath:String(value[..<range.upperBound].dropLast()))}
            result.append(StartupItem(url:url,label:label,owner:identity.owner,source:source,loaded:loadedState,disabled:disabledResult.succeeded ? parseDisabled(disabledResult.output,label:label) : nil,command:command,identity:identity,applicationURL:appURL))
        } }
        let protected=try await ProtectionBackend.protectedIdentifiers(result.map(\.label))
        return result.map {item in StartupItem(url:item.url,label:item.label,owner:item.owner,source:item.source,loaded:item.loaded,disabled:item.disabled,command:item.command,identity:item.identity,applicationURL:item.applicationURL,isProtected:protected.contains(item.label))}.sorted { $0.label < $1.label }
    }
    public static func set(_ item: StartupItem, disabled: Bool, policy:PathPolicy = .standard, protect:@Sendable ([String]) async throws -> Set<String> = {try await ProtectionBackend.protectedIdentifiers($0)}, execute:@Sendable (String,[String],TimeInterval) async throws -> CommandResult = {try await CommandRunner.run($0,$1,timeout:$2)}) async -> ItemOutcome {
        do {
            guard item.controllable else { throw BonsaiError.refused("Only current-user LaunchAgents with measured state support controls. Use Login Items in System Settings for managed items.") }
            let protected=try await protect([item.label])
            guard protected.isEmpty else {throw BonsaiError.refused("Bonsai protects this system or vendor-managed service. Use System Settings or the vendor app.")}
            try policy.validate(item.url,expected:item.identity)
            let domain = "gui/\(getuid())"; let target = domain + "/" + item.label
            let currentState = try await execute("/bin/launchctl",["print-disabled",domain],10)
            guard currentState.succeeded, parseDisabled(currentState.output,label:item.label) == item.disabled else { throw BonsaiError.changed("Startup state changed since review. Refresh and try again.") }
            let change = try await execute("/bin/launchctl",[disabled ? "disable" : "enable",target],15)
            guard change.succeeded else { throw BonsaiError.unavailable(change.output) }
            let action = try await execute("/bin/launchctl",disabled ? ["bootout",target] : ["bootstrap",domain,item.url.path],15)
            let check = try await execute("/bin/launchctl",["print-disabled",domain],10)
            let verify = check.succeeded && parseDisabled(check.output,label:item.label) == disabled
            return ItemOutcome(title:item.label,path:item.id,status:verify ? (action.succeeded ? "Changed" : "Persistent state changed; session action failed") : "Verification failed",detail:"Persistent state: \(disabled ? "disabled" : "enabled"). Session command exit \(action.status): \(action.output). Recheck the Startup list for actual loaded state. Restore with the opposite control; originally \(item.state). Restoration commands: \(restorationCommands(item).map { (["launchctl"]+$0).joined(separator:" ") }.joined(separator:"; ")). Log out and back in if a job remains active.")
        } catch { return ItemOutcome(title:item.label,path:item.id,status:"Failed",detail:error.localizedDescription) }
    }
}
