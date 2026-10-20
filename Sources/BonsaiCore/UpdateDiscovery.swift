import Foundation

public struct FeedRelease: Sendable {
    public var download:URL?;public var signature:String?;public var length:UInt64?;public var fullArchive=true
    public var build=""; public var version=""; public var minimumSystem=""; public var maximumSystem=""; public var hardware=""; public var notes:URL?; public var title=""; public var channel=""; public var macOS=true
    public init() {}
}
public enum VersionOrder {
    public static func newer(_ candidate:String, than installed:String) -> Bool {
        guard !candidate.isEmpty,!installed.isEmpty,candidate != "Unknown",installed != "Unknown" else { return false }
        // Ambiguous versions are not guessed; publisher updater remains authoritative.
        let cleanedCandidate=candidate.replacingOccurrences(of:"Build ",with:"")
        let a=cleanedCandidate.hasPrefix("v") ? String(cleanedCandidate.dropFirst()) : cleanedCandidate
        let cleanedInstalled=installed.replacingOccurrences(of:"Build ",with:"")
        let b=cleanedInstalled.hasPrefix("v") ? String(cleanedInstalled.dropFirst()) : cleanedInstalled
        guard a.range(of:"^[0-9]+(?:[.,][0-9]+)*(?:-[0-9]+)?$",options:.regularExpression) != nil,b.range(of:"^[0-9]+(?:[.,][0-9]+)*(?:-[0-9]+)?$",options:.regularExpression) != nil else { return false }
        let aa=a.split(whereSeparator:{$0=="." || $0=="," || $0=="-"}).map(String.init);let bb=b.split(whereSeparator:{$0=="." || $0=="," || $0=="-"}).map(String.init)
        for i in 0..<max(aa.count,bb.count) { let x=i<aa.count ? aa[i] : "0";let y=i<bb.count ? bb[i] : "0";guard let n=UInt64(x),let m=UInt64(y) else { return false };if n != m { return n>m } }
        return false
    }
}
private final class AppcastReader:NSObject,XMLParserDelegate {
    var deltaDepth=0
    var items:[FeedRelease]=[]; var current:FeedRelease?; var field=""; var text=""
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName qName:String?,attributes:[String:String]) {
        field=name.components(separatedBy:":").last ?? name; text=""
        if field=="item" { current=FeedRelease() }
        if field=="deltas" {deltaDepth+=1}
        if field=="enclosure",current != nil,deltaDepth==0 {
            if let value=attributes["url"] {current?.download=URL(string:value)}
            current?.signature=attributes["sparkle:edSignature"]
            current?.length=attributes["length"].flatMap(UInt64.init)
            current?.fullArchive=attributes["sparkle:deltaFrom"]==nil && !["package","guided-package"].contains(attributes["sparkle:installationType"] ?? "")
            if let build=attributes["sparkle:version"] { current?.build=build }
            if let version=attributes["sparkle:shortVersionString"] { current?.version=version }
            if let os=attributes["sparkle:os"],os.lowercased() != "macos" { current?.macOS=false }
        }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) { if text.utf8.count<16_384 { text += string } }
    func parser(_ parser:XMLParser,foundCDATA data:Data) { if text.utf8.count<16_384 { text += String(decoding:data,as:UTF8.self) } }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName qName:String?) {
        let leaf=name.components(separatedBy:":").last ?? name; let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if leaf=="deltas" {deltaDepth=max(0,deltaDepth-1)}
        switch leaf { case "version":current?.build=value; case "shortVersionString":current?.version=value; case "minimumSystemVersion":current?.minimumSystem=value; case "maximumSystemVersion":current?.maximumSystem=value; case "hardwareRequirements":current?.hardware=value; case "releaseNotesLink":current?.notes=URL(string:value); case "title":current?.title=value; case "channel":current?.channel=value; case "item":if let current { items.append(current) }; current=nil; default:break }
        field=""; text=""
    }
    func parser(_ parser:XMLParser,resolveExternalEntityName name:String,systemID:String?) -> Data? { nil }
}
public enum AppcastMetadata {
    public static func parse(_ data:Data) throws -> [FeedRelease] {
        guard data.count<=2_097_152,!String(decoding:data,as:UTF8.self).localizedCaseInsensitiveContains("<!DOCTYPE") else { throw BonsaiError.refused("Oversized appcast or external document declarations are not accepted.") }
        let reader=AppcastReader(); let parser=XMLParser(data:data); parser.shouldResolveExternalEntities=false; parser.delegate=reader
        guard parser.parse() else { throw BonsaiError.unavailable("Appcast XML could not be parsed.") }
        return reader.items.filter { $0.macOS && ["","stable"].contains($0.channel.lowercased()) }
    }
    public static func update(app:InstalledApp, data:Data, feed:URL, systemVersion:String) throws -> SoftwareUpdate? {
        let build=Bundle(url:app.url)?.infoDictionary?["CFBundleVersion"] as? String ?? app.version
        let releases=try parse(data).filter { !VersionOrder.newer($0.minimumSystem,than:systemVersion) && ($0.maximumSystem.isEmpty || !VersionOrder.newer(systemVersion,than:$0.maximumSystem)) && ($0.hardware.isEmpty || $0.hardware=="arm64") }
        let latest=releases.filter { release in
            if VersionOrder.newer(release.version,than:app.version) {return true}
            if VersionOrder.newer(app.version,than:release.version) {return false}
            return VersionOrder.newer(release.build,than:build)
        }.sorted { a,b in
            let av=a.version.isEmpty ? a.build : a.version,bv=b.version.isEmpty ? b.build : b.version
            return av==bv ? VersionOrder.newer(a.build,than:b.build) : VersionOrder.newer(av,than:bv)
        }.first
        guard let latest else { return nil }
        let archive=latest.download.flatMap {latest.fullArchive && PublicMetadataHTTP.valid($0) && ["zip","dmg"].contains($0.pathExtension.lowercased()) ? $0 : nil}
        return SoftwareUpdate(id:"feed:"+app.bundleID,name:app.name,installed:app.version,available:latest.version.isEmpty ? "Build "+latest.build : latest.version,source:"Sparkle",information:latest.title+". Publisher Sparkle feed. Supported full ZIP and DMG releases install directly after archive and publisher validation.",applicationURL:app.url,sourceURL:feed,releaseNotesURL:latest.notes.flatMap { PublicMetadataHTTP.valid($0) ? $0 : nil },downloadURL:archive,downloadSignature:latest.signature,downloadBytes:latest.length,availableBuild:latest.build)
    }
}
public enum AppStoreMetadata {
    public static func parse(_ data:Data, app:InstalledApp) throws -> SoftwareUpdate? {
        guard data.count<=2_097_152 else { throw BonsaiError.refused("Oversized catalog response.") }
        let json=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let matching=(json?["results"] as? [[String:Any]] ?? []).filter {$0["bundleId"] as? String==app.bundleID}
        let entry=matching.first {$0["kind"] as? String=="mac-software"} ?? matching.first {$0["kind"] as? String=="software"}
        guard let entry,let version=entry["version"] as? String,VersionOrder.newer(version,than:app.version) else {return nil}
        let link=(entry["trackViewUrl"] as? String).flatMap(URL.init(string:))
        let safe=link.flatMap { $0.host=="apps.apple.com" && PublicMetadataHTTP.valid($0) ? $0 : nil }
        return SoftwareUpdate(id:"store:"+app.bundleID,name:app.name,installed:app.version,available:version,source:"App Store",information:String((entry["releaseNotes"] as? String ?? "Public App Store catalog version. Availability may differ by account and storefront.").prefix(3000)),applicationURL:app.url,sourceURL:safe)
    }
}
private final class MetadataRedirectGuard:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?) -> Void) { completionHandler(request.url.map(PublicMetadataHTTP.valid)==true ? request : nil) }
}
public enum PublicMetadataHTTP {
    public static func valid(_ url:URL) -> Bool {
        guard url.scheme=="https",url.user==nil,url.password==nil,url.port==nil || url.port==443,let h=url.host?.lowercased(),h.contains("."),h != "localhost",!h.hasSuffix(".local"),!h.hasSuffix(".internal"),!h.contains(":"),!h.allSatisfy({$0.isNumber || $0=="."}) else { return false }
        return true
    }
    public static func get(_ url:URL, consent:Bool) async throws -> Data {
        guard consent else { throw BonsaiError.refused("Network consent is required for update metadata.") }; guard valid(url) else { throw BonsaiError.refused("Only public HTTPS metadata sources without embedded credentials are supported.") }
        let config=URLSessionConfiguration.ephemeral; config.httpShouldSetCookies=false; config.urlCredentialStorage=nil; config.timeoutIntervalForRequest=10; config.timeoutIntervalForResource=12; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session=URLSession(configuration:config,delegate:MetadataRedirectGuard(),delegateQueue:nil); defer { session.invalidateAndCancel() }
        var request=URLRequest(url:url); request.setValue("Bonsai/1.1 metadata-check",forHTTPHeaderField:"User-Agent"); let (stream,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),response.url.map(valid)==true else { throw BonsaiError.unavailable("Update source returned an unavailable or unsupported response.") }
        guard response.expectedContentLength<=2_097_152 else { throw BonsaiError.refused("Update metadata response is too large.") }
        var data=Data(); for try await byte in stream { try Task.checkCancellation(); guard data.count<2_097_152 else { throw BonsaiError.refused("Update metadata response exceeded its size limit.") }; data.append(byte) }; return data
    }
}
public struct MetadataCheckReport:Sendable, Codable { public let updates:[SoftwareUpdate]; public let notes:[String]; public let checked:Int; public let appStates:[String:String]?; public init(updates:[SoftwareUpdate],notes:[String],checked:Int,appStates:[String:String]?=nil) {self.updates=updates;self.notes=notes;self.checked=checked;self.appStates=appStates} }
public enum UpdateDiscovery {
    public static func check(_ apps:[InstalledApp],consent:Bool,publicCatalogConsent:Bool=false,progress:@Sendable (MetadataCheckReport) async -> Void = {_ in},fetch:@escaping @Sendable (URL) async throws -> Data = { try await PublicMetadataHTTP.get($0,consent:true) }) async throws -> MetadataCheckReport {
        guard consent else { throw BonsaiError.refused("Network consent is required for installed app update checks.") }
        let os=ProcessInfo.processInfo.operatingSystemVersion; let system="\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let candidates=apps.filter { $0.appStore || declaredFeed($0) != nil || ElectronMetadata.manifestURL(app:$0) != nil || (publicCatalogConsent && PublicCaskUpdates.source($0) != nil) }
        let end=ProcessInfo.processInfo.systemUptime+120
        var updates:[SoftwareUpdate]=[];var notes:[String]=[];var checked=0;var states:[String:String]=[:]
        // Three concurrent bounded requests cover the whole inventory rather than
        // stopping after ten App Store apps or a slow alphabetical prefix.
        let bounded=Array(candidates.prefix(128))
        try await withThrowingTaskGroup(of: MetadataCheckReport.self) { group in
            var next=0
            func add(_ app:InstalledApp) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let update:SoftwareUpdate?
                        if app.appStore {
                            var url=URLComponents(string:"https://itunes.apple.com/lookup")!
                            url.queryItems=[URLQueryItem(name:"bundleId",value:app.bundleID),URLQueryItem(name:"entity",value:"macSoftware"),URLQueryItem(name:"country",value:Locale.current.region?.identifier ?? "US")]
                            update=try AppStoreMetadata.parse(await fetch(url.url!),app:app)
                        } else if let feed=declaredFeed(app) {
                            update=try AppcastMetadata.update(app:app,data:await fetch(feed),feed:feed,systemVersion:system)
                        } else if let manifest=ElectronMetadata.manifestURL(app:app) {
                            update=try ElectronMetadata.update(app:app,data:await fetch(manifest),source:manifest)
                        } else if publicCatalogConsent,let source=PublicCaskUpdates.source(app) {
                            update=try PublicCaskUpdates.parse(await fetch(source),app:app)
                        } else {update=nil}
                        return MetadataCheckReport(updates:update.map {[$0]} ?? [],notes:[],checked:1,appStates:[app.id:update==nil ? "No update detected" : "Update available"])
                    } catch is CancellationError {throw CancellationError()}
                    catch {
                        let primaryError=error.localizedDescription
                        if publicCatalogConsent,let source=PublicCaskUpdates.source(app) {
                            do {let fallback=try PublicCaskUpdates.parse(await fetch(source),app:app);return MetadataCheckReport(updates:fallback.map {[$0]} ?? [],notes:[app.name+": publisher source unavailable; used public cask catalog. "+primaryError],checked:1,appStates:[app.id:fallback==nil ? "No update in catalog" : "Update available"])} catch is CancellationError {throw CancellationError()} catch {}
                        }
                        return MetadataCheckReport(updates:[],notes:[app.name+": "+primaryError],checked:1,appStates:[app.id:"Couldn’t check"])
                    }
                }
            }
            while next<min(3,bounded.count) {add(bounded[next]);next+=1}
            while let report=try await group.next() {
                try Task.checkCancellation();updates+=report.updates;notes+=report.notes;checked+=report.checked;states.merge(report.appStates ?? [:],uniquingKeysWith: {_,new in new})
                await progress(MetadataCheckReport(updates:updates,notes:notes,checked:checked,appStates:states))
                if next<bounded.count,ProcessInfo.processInfo.systemUptime<end {add(bounded[next]);next+=1}
            }
            if next<candidates.count {notes.append("\(candidates.count-next) sources were not checked within the 128-source / 120-second scheduling limit. Refresh to retry.")}
        }
        notes.append("\(checked) of \(candidates.count) declared sources checked. App Store results use the public \(Locale.current.region?.identifier ?? "US") catalog; availability can differ by account. Apps without a supported source are labeled separately. No packages downloaded.")
        return MetadataCheckReport(updates:updates,notes:notes,checked:checked,appStates:states)
    }
    public static func declaredFeed(_ app:InstalledApp)->URL? {
        let info=Bundle(url:app.url)?.infoDictionary
        if let feed=(info?["SUFeedURL"] as? String).flatMap(URL.init(string:)),PublicMetadataHTTP.valid(feed) {return feed}
        // Public publisher feed observed in Bonsai; a pinned host identity and its
        // installed Ed25519 key still authenticate every downloaded release.
        if app.bundleID=="com.openai.codex",let key=info?["SUPublicEDKey"] as? String,Data(base64Encoded:key)?.count==32 {return URL(string:"https://persistent.oaistatic.com/codex-app-prod/appcast.xml")}
        return nil
    }
}
