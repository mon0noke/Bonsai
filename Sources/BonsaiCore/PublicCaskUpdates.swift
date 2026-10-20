import Foundation

/// Public cask metadata also covers apps installed outside Homebrew. It never
/// adopts them into Homebrew. App-only downloads require a checksum and the
/// installed publisher signature; package scripts are never executed.
public enum PublicCaskUpdates {
    public static let tokens:[String:String]=[
        "org.cryptomator":"cryptomator","com.hnc.Discord":"discord","io.ente.auth.mac":"ente-auth",
        "net.imput.helium":"helium-browser","org.libreoffice.script":"libreoffice","org.localsend.localsendApp":"localsend",
        "com.objective-see.lulu.app":"lulu","me.grishka.NearDrop":"neardrop","md.obsidian":"obsidian",
        "com.raycast.macos":"raycast","com.Meltytech.Shotcut":"shotcut","com.sublimetext.4":"sublime-text",
        "io.tailscale.ipn.macsys":"tailscale-app","com.objective-see.taskexplorer":"taskexplorer",
        "org.vim.MacVim":"macvim","io.ganeshrvel.openmtp":"openmtp","com.obsproject.obs-studio":"obs",
        "com.colliderli.iina":"iina","com.aone.keka":"keka","com.ranchero.NetNewsWire-Evergreen":"netnewswire",
        "com.googlecode.iterm2":"iterm2","com.corecode.UninstallPKG":"uninstallpkg","org.sveinbjorn.Platypus":"platypus",
        "com.github.xor-gate.syncthing-macosx":"syncthing-app","ch.protonvpn.mac":"protonvpn",
        "com.amazon.Lassen":"kindle","com.bitwarden.desktop":"bitwarden","com.firecore.infuse":"infuse"
    ]
    public static func source(_ app:InstalledApp)->URL? {
        tokens[app.bundleID].flatMap {URL(string:"https://formulae.brew.sh/api/cask/"+$0+".json")}
    }
    public static func parse(_ data:Data,app:InstalledApp) throws -> SoftwareUpdate? {
        guard data.count<=2_097_152,let token=tokens[app.bundleID],let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],json["token"] as? String==token,let version=json["version"] as? String else {throw BonsaiError.unavailable("Catalog identity could not be established.")}
        guard json["disabled"] as? Bool != true else {throw BonsaiError.unavailable("This app is disabled in the public cask catalog. Check its publisher.")}
        let artifacts=json["artifacts"] as? [[String:Any]] ?? []
        let names=artifacts.compactMap {($0["app"] as? [String])?.first}.map {URL(fileURLWithPath:$0).lastPathComponent}
        guard names.contains(where:{$0.caseInsensitiveCompare(app.url.lastPathComponent) == .orderedSame}) else {throw BonsaiError.unavailable("Catalog package does not match this installed app.")}
        let pieces=version.split(separator:",").map(String.init)
        let build=Bundle(url:app.url)?.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let candidate=pieces.first ?? version
        let newer=VersionOrder.newer(candidate,than:app.version) || (pieces.count>1 && !VersionOrder.newer(app.version,than:candidate) && VersionOrder.newer(pieces[1],than:build))
        guard newer else {return nil}
        let homepage=(json["homepage"] as? String).flatMap(URL.init(string:)).flatMap {PublicMetadataHTTP.valid($0) ? $0 : nil}
        let checksum=(json["sha256"] as? String).flatMap {$0.range(of:"^[0-9a-fA-F]{64}$",options:.regularExpression) != nil ? $0.lowercased():nil}
        let download=(json["url"] as? String).flatMap(URL.init(string:)).flatMap {PublicMetadataHTTP.valid($0) && ["zip","dmg"].contains($0.pathExtension.lowercased()) ? $0:nil}
        let appOnly=artifacts.allSatisfy {artifact in artifact.keys.allSatisfy {["app","target","zap","uninstall"].contains($0)} && (artifact["target"]==nil || artifact["app"] != nil)}
        return SoftwareUpdate(id:"catalog:"+app.bundleID,name:app.name,installed:app.version,available:version,source:homepage == nil ? "Homebrew catalog" : "Website",information:"Public Homebrew catalog release, matched to this bundle identifier and app artifact. May lag the publisher. Supported app-only ZIP and DMG downloads install in Bonsai after checksum and publisher verification.",applicationURL:app.url,sourceURL:homepage ?? URL(string:"https://formulae.brew.sh/cask/"+token),downloadURL:appOnly && checksum != nil ? download:nil,downloadSHA256:appOnly ? checksum:nil)
    }
}

public enum SoftwareUpdateBatch {
    public static func plan(_ items:[SoftwareUpdate])->[SoftwareUpdate] {BrewCatalog.merge(items,preferInstallable:true)}
    public static func run(_ items:[SoftwareUpdate],progress:@Sendable (Int,SoftwareUpdate) async -> Void = {_,_ in},install:@Sendable (SoftwareUpdate) async -> ItemOutcome,handoff:@Sendable (SoftwareUpdate) async -> Bool) async -> [ItemOutcome] {
        var results:[ItemOutcome]=[]
        for (i,item) in plan(items).enumerated() {
            if Task.isCancelled {results.append(ItemOutcome(title:item.name,path:item.id,status:"Skipped",detail:"Cancelled before this update started."));continue}
            await progress(i,item)
            if Task.isCancelled {results.append(ItemOutcome(title:item.name,path:item.id,status:"Skipped",detail:"Cancelled before this update started."));continue}
            if item.canInstall {results.append(await install(item))}
            else {let opened=await handoff(item);results.append(ItemOutcome(title:item.name,path:item.id,status:opened ? "Opened updater" : "Unavailable",detail:opened ? "Opened the publisher application or App Store. Complete the update there; installation has not been verified." : "The supported update destination could not be opened. Refresh or visit the publisher."))}
        }
        return results
    }
}
