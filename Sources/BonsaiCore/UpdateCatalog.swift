import Foundation

/// Deliberately small metadata subset. YAML objects, aliases and executable
/// configuration are never evaluated; unsupported publishers use their updater.
public enum ElectronMetadata {
    public static func fields(_ data:Data)->[String:String] {
        guard data.count<=65_536 else {return [:]}
        var result:[String:String]=[:]
        for line in String(decoding:data,as:UTF8.self).split(separator:"\n") {
            guard line.first?.isWhitespace != true,let colon=line.firstIndex(of:":") else {continue}
            let key=String(line[..<colon]);var value=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'") {value=String(value.dropFirst().dropLast())}
            if ["provider","url","owner","repo","channel","private","version","releaseName","path","sha512"].contains(key),value.count<2048 {result[key]=value}
        }
        return result
    }
    public static func manifestURL(app:InstalledApp)->URL? {
        let file=app.url.appendingPathComponent("Contents/Resources/app-update.yml")
        guard let identity=try? Identity.read(file),!identity.isSymlink,identity.size<=65_536,let data=try? Data(contentsOf:file) else {return nil}
        return manifestURL(configuration:data)
    }
    public static func manifestURL(configuration:Data)->URL? {
        let config=fields(configuration);guard config["private"]?.lowercased() != "true" else {return nil}
        let channel=config["channel"] ?? "latest"
        guard channel.range(of:"^[a-z0-9][a-z0-9-]{0,40}$",options:.regularExpression) != nil else {return nil}
        if config["provider"]=="generic",let base=config["url"].flatMap(URL.init(string:)),PublicMetadataHTTP.valid(base),base.query==nil,base.fragment==nil {
            return base.appendingPathComponent(channel+"-mac.yml")
        }
        if config["provider"]=="github",let owner=config["owner"],let repo=config["repo"], [owner,repo].allSatisfy({$0.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$",options:.regularExpression) != nil}) {
            return URL(string:"https://github.com/\(owner)/\(repo)/releases/latest/download/\(channel)-mac.yml")
        }
        return nil
    }
    public static func archive(_ data:Data,source:URL)->(URL,String)? {
        guard data.count<=65_536 else {return nil}
        var candidates:[(String,String)]=[];var current:String?
        let top=fields(data)
        if let path=top["path"],let hash=top["sha512"] {candidates.append((path,hash))}
        for line in String(decoding:data,as:UTF8.self).split(separator:"\n") {
            let value=line.trimmingCharacters(in:.whitespaces)
            if value.hasPrefix("- url:") {current=String(value.dropFirst(6)).trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"\"'"))}
            else if value.hasPrefix("sha512:"),let path=current {candidates.append((path,String(value.dropFirst(7)).trimmingCharacters(in:.whitespacesAndNewlines)));current=nil}
        }
        return candidates.sorted {$0.0.contains("arm64") && !$1.0.contains("arm64")}.compactMap {path,hash -> (URL,String)? in
            guard let url=URL(string:path,relativeTo:source)?.absoluteURL,PublicMetadataHTTP.valid(url),["zip","dmg"].contains(url.pathExtension.lowercased()),!path.contains("x64"),!path.contains("x86_64"),Data(base64Encoded:hash)?.count==64 else {return nil}
            return (url,hash)
        }.first
    }
    public static func update(app:InstalledApp,data:Data,source:URL)throws->SoftwareUpdate? {
        guard PublicMetadataHTTP.valid(source),data.count<=65_536 else {throw BonsaiError.refused("Unsupported Electron metadata source or size.")}
        guard let version=fields(data)["version"] else {throw BonsaiError.unavailable("Electron source did not contain a supported version.")}
        guard VersionOrder.newer(version,than:app.version) else {return nil}
        let artifact=archive(data,source:source)
        return SoftwareUpdate(id:"electron:"+app.bundleID,name:app.name,installed:app.version,available:version,source:"Electron",information:"Publisher release metadata. Supported ZIP updates are verified against the installed publisher signature before replacement.",applicationURL:app.url,sourceURL:source,downloadURL:artifact?.0,downloadSHA512:artifact?.1)
    }
}

public enum BrewCatalog {
    public struct TapRelease:Sendable {public let token:String;public let version:String;public let homepage:URL?}
    public static func literalRelease(_ text:String)->TapRelease? {
        guard text.utf8.count<=65_536 else {return nil}
        func literal(_ key:String)->String? {
            let escaped=NSRegularExpression.escapedPattern(for:key)
            guard let regex=try? NSRegularExpression(pattern:"(?m)^\\s*"+escaped+"\\s+\"([^\"\\r\\n]+)\""),let m=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else {return nil}
            let value=String(text[range]);return value.contains("#{") ? nil : value
        }
        guard let token=literal("cask"),token.range(of:"^[a-z0-9][a-z0-9+@._-]*$",options:.regularExpression) != nil,let version=literal("version") else {return nil}
        return TapRelease(token:token,version:version,homepage:literal("homepage").flatMap(URL.init(string:)).flatMap {PublicMetadataHTTP.valid($0) ? $0 : nil})
    }
    public static func localTapReleases(root:URL)->[String:TapRelease] {
        var queue=[(root,0)],count=0;var records:[String:[TapRelease]]=[:];let deadline=ProcessInfo.processInfo.systemUptime+3
        while let (url,depth)=queue.popLast(),count<3000,ProcessInfo.processInfo.systemUptime<deadline {
            count+=1;guard !Task.isCancelled,let id=try? Identity.read(url),!id.isSymlink else {continue}
            if id.isDirectory,depth<5 {queue+=(try? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).map {($0,depth+1)}) ?? []}
            else if url.pathExtension=="rb",id.size<=65_536,let data=try? Data(contentsOf:url),let release=literalRelease(String(decoding:data,as:UTF8.self)) {records[release.token,default:[]].append(release)}
        }
        return records.compactMapValues {$0.count==1 ? $0.first : nil}
    }

    public static func updates(_ data:Data,apps:[InstalledApp],taps:[String:TapRelease]=[:])throws->[SoftwareUpdate] {
        guard data.count<=2_097_152,let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],let casks=json["casks"] as? [[String:Any]] else {throw BonsaiError.unavailable("Homebrew catalog was incomplete or unreadable.")}
        return casks.compactMap {cask in
            guard let token=cask["token"] as? String,token.range(of:"^[a-z0-9][a-z0-9+@._-]*$",options:.regularExpression) != nil,
                let catalogVersion=cask["version"] as? String,let installed=cask["installed"] as? String,!installed.isEmpty else {return nil}
            let artifacts=cask["artifacts"] as? [[String:Any]] ?? []
            let appNames=artifacts.compactMap {($0["app"] as? [String])?.first}.map {URL(fileURLWithPath:$0).lastPathComponent}
            let matches=apps.filter {appNames.contains($0.url.lastPathComponent)}
            guard matches.count<=1 else {return nil}
            let app=matches.first
            if !appNames.isEmpty && app==nil {return nil} // A missing cask app is not an installed app update.
            let tap=taps[token].flatMap {VersionOrder.newer($0.version,than:catalogVersion) ? $0 : nil}
            let available=tap?.version ?? catalogVersion
            let availableParts=available.split(separator:",").map(String.init)
            let installedParts=installed.split(separator:",").map(String.init)
            var current=app?.version ?? installed
            if let app,let build=Bundle(url:app.url)?.infoDictionary?["CFBundleVersion"] as? String,
                installedParts.first==build && installedParts.first != app.version {current=build}
            let candidate=availableParts.first ?? available
            guard VersionOrder.newer(candidate,than:current) || (app==nil && cask["outdated"] as? Bool==true) else {return nil}
            let name=app?.name ?? (cask["name"] as? [String])?.first ?? token
            let packageURL=(cask["url"] as? String).flatMap(URL.init(string:)).flatMap {PublicMetadataHTTP.valid($0) && $0.pathExtension.lowercased()=="pkg" ? $0:nil}
            let checksum=(cask["sha256"] as? String).flatMap {$0.range(of:"^[0-9a-fA-F]{64}$",options:.regularExpression) != nil ? $0.lowercased():nil}
            let package=tap==nil && packageURL != nil && checksum != nil && artifacts.contains {$0["pkg"] != nil}
            if package {
                let receipts=artifacts.flatMap {($0["uninstall"] as? [[String:Any]]) ?? []}.flatMap {record -> [String] in
                    if let id=record["pkgutil"] as? String {return [id]}
                    return record["pkgutil"] as? [String] ?? []
                }
                if receipts.contains(where:{id in PackageReceipt.version(id).map {!VersionOrder.newer(candidate,than:$0)} ?? false}) {return nil}
            }
            return SoftwareUpdate(id:token,name:name,installed:app?.version ?? installed,available:available,source:package ? "Homebrew package":tap==nil ? "Homebrew cask" : "Homebrew tap",information:package ? "Download the verified package, then open macOS Installer explicitly." : tap != nil ? "Local tap release metadata. Open the publisher download page." : "Homebrew-managed update.",applicationURL:app?.url,sourceURL:tap?.homepage ?? URL(string:"https://formulae.brew.sh/cask/"+token),downloadURL:package ? packageURL:nil,downloadSHA256:package ? checksum:nil)

        }
    }
    /// One row per physical app, preferring its publisher/App Store source over a
    /// duplicate package-manager notice. Packages keep their own source identity.
    public static func merge(_ items:[SoftwareUpdate],preferInstallable:Bool=false)->[SoftwareUpdate] {
        func priority(_ item:SoftwareUpdate)->Int {item.source=="App Store" ? 0 : preferInstallable && item.canInstall ? 1 : item.usesSparkle ? 2 : item.source=="Electron" ? 3 : 4}
        var seen=Set<String>()
        return items.sorted {priority($0)<priority($1)}.filter {item in seen.insert(item.applicationURL.map {physicalURL($0).path} ?? item.source+":"+item.id).inserted}.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
}
