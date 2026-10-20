import Foundation

public struct CleanReport: Sendable {
    public let items: [ReviewItem]; public let issues: [String]; public let completeWithinCatalog: Bool
    public let deniedDiscoveryPaths:[String]
    public var accessDeniedPaths:[String] {Array(Set(deniedDiscoveryPaths+items.flatMap {$0.measurement.accessDeniedPaths ?? []})).sorted()}
    public init(items:[ReviewItem],issues:[String],completeWithinCatalog:Bool,deniedDiscoveryPaths:[String]=[]) { self.items=items;self.issues=issues;self.completeWithinCatalog=completeWithinCatalog;self.deniedDiscoveryPaths=deniedDiscoveryPaths }
}
public enum CleanCatalog {
    public static func classify(_ name:String) -> (String,[String]) {
        let n=name.lowercased()
        let families:[(String,[String],[String])]=[
            ("Browsers",["chrome"],["com.google.Chrome","com.google.Chrome.beta","com.google.Chrome.canary"]),("Browsers",["safari"],["com.apple.Safari"]),("Browsers",["firefox"],["org.mozilla.firefox"]),("Browsers",["brave"],["com.brave.Browser"]),("Browsers",["edgemac","microsoft edge"],["com.microsoft.edgemac"]),("Browsers",["helium"],["net.imput.helium"]),("Browsers",["zen"],["app.zen-browser.zen"]),("Browsers",["vivaldi"],["com.vivaldi.Vivaldi"]),("Browsers",["thebrowser","dia"],["company.thebrowser.Browser","company.thebrowser.dia"]),("Browsers",["opera"],["com.operasoftware.Opera"]),
            ("AI tools",["claude","anthropic"],["com.anthropic.claudefordesktop"]),("AI tools",["cursor","todesktop"],["com.todesktop.230313mzl4w4u92"]),("AI tools",["codex"],["com.openai.codex"]),("AI tools",["openai","chatgpt"],["com.openai.chat"]),("AI tools",["opencode"],["ai.opencode.desktop"]),("AI tools",["ollama"],["com.ollama.ollama"]),
            ("Communication",["slack","tinyspeck"],["com.tinyspeck.slackmacgap"]),("Communication",["discord"],["com.hnc.Discord"]),("Communication",["teams"],["com.microsoft.teams2","com.microsoft.teams"]),("Communication",["zoom"],["us.zoom.xos"]),("Communication",["telegram"],["ru.keepcoder.Telegram"]),
            ("Cloud clients",["com.apple.bird","cloudkit"],["com.apple.bird"]),("Cloud clients",["dropbox"],["com.getdropbox.dropbox"]),("Cloud clients",["onedrive"],["com.microsoft.OneDrive"]),("Cloud clients",["drivefs","googledrive"],["com.google.drivefs"]),("Cloud clients",["com.box."],["com.box.desktop"]),
            ("Design tools",["figma"],["com.figma.Desktop"]),("Design tools",["adobe"],["com.adobe.*"]),("Design tools",["sketch","bohemiancoding"],["com.bohemiancoding.sketch3"]),("Design tools",["affinity"],["com.seriflabs.*"]),
            ("Misc",["steam"],["com.valvesoftware.steam"]),("Games & media",["spotify"],["com.spotify.client"]),("Games & media",["vlc"],["org.videolan.vlc"]),("Games & media",["iina","colliderli"],["com.colliderli.iina"]),("Games & media",["podcasts"],["com.apple.podcasts"]),
            ("Productivity",["notion"],["notion.id"]),("Productivity",["obsidian"],["md.obsidian"]),("Productivity",["logseq"],["com.electron.logseq"]),
            ("Developer artifacts",["/code/"],["com.microsoft.VSCode"]),("Developer artifacts",["homebrew"],[]),("Developer artifacts",["xcode"],["com.apple.dt.Xcode"]),("Developer artifacts",["jetbrains"],["com.jetbrains.*"]),("Developer artifacts",["zed"],["dev.zed.Zed"]),("Developer artifacts",["warp"],["dev.warp.Warp-Stable"]),("Developer artifacts",["ghostty"],["com.mitchellh.ghostty"]),("Developer artifacts",["cocoapods","deno","pnpm","yarn"],[])]
        for (category,words,ids) in families where words.contains(where:n.contains) { return (category,ids) }
        return ("Application caches",[name])
    }
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, exclusions: [String] = [], temporaryRoot:URL=URL(fileURLWithPath:NSTemporaryDirectory()), systemRoot:URL?=nil, activity:@escaping @Sendable(CleanScanActivity)->Void={_ in}, progress: @Sendable (String, Int) -> Void = { _,_ in }) throws -> CleanReport {
        let exclusions=exclusions.map { physicalURL(URL(fileURLWithPath:$0)).path }
        var issues: [String] = []; var discoveryComplete = true;var denied:[String]=[]
        func list(_ root: URL) -> [URL] {
            guard FileManager.default.fileExists(atPath:root.path) else { return [] }
            do { let contents=try DirectoryListing.read(root,limit:20_000,expected:Identity.read(root),deadlineUptime:ProcessInfo.processInfo.systemUptime+10);if !contents.complete {discoveryComplete=false;issues.append(root.path+": discovery limit reached.")};return contents.urls } catch { discoveryComplete=false; issues.append("\(root.path): \(error.localizedDescription)");if FileAccess.isPermission(error) {denied.append(root.path)}; return [] }
        }
        var candidates: [(URL,String,String,[String])] = []
        let cache = home.appendingPathComponent("Library/Caches")
        do { let children = list(cache)
            for child in children where !(AppIdentity.protectedFolderNames+["CloudKit"]).contains(child.lastPathComponent) {
                let (category,ids) = classify(child.lastPathComponent)
                candidates.append((child,category,"Rebuildable application cache. Quit the related app first; offline content may be downloaded again.",ids))
            }
        }
        let logs = home.appendingPathComponent("Library/Logs")
        do { let children = list(logs)
            for child in children { candidates.append((child,"Logs","Diagnostic logs. Removing them limits troubleshooting history.",[])) }
        }
        let targeted: [(String,String,String)] = [
            ("Library/Developer/Xcode/DerivedData","Developer artifacts","Xcode build intermediates. Builds and indexing will take longer afterward."),
            ("Library/Developer/Xcode/Archives","Developer artifacts","Distribution archives may be needed for symbolication. High risk; retain important releases."),
            (".npm/_cacache","Developer artifacts","npm package cache; dependencies must be downloaded again."),
            (".cache/pip","Developer artifacts","Python package download cache."),
            (".cache/huggingface/hub","AI tools","Downloaded AI models. Large downloads and offline capabilities may be lost."),
            (".cache/uv","Developer artifacts","uv package and build cache."),
            ("Library/Application Support/Code/Cache","Developer artifacts","Visual Studio Code browser cache."),
            ("Library/Application Support/Cursor/Cache","AI tools","Cursor browser cache. Does not include conversations or credentials."),
            ("Library/Application Support/Claude/Cache","AI tools","Claude desktop browser cache. Does not include conversations."),
            ("Library/Application Support/Slack/Cache","Communication","Slack downloaded cache; offline content may need fetching again."),
            ("Library/Application Support/discord/Cache","Communication","Discord browser cache."),
            ("Library/Application Support/Figma/Cache","Design tools","Figma browser cache. Close Figma before cleaning.")
        ]
        for (path,category,explanation) in targeted {
            let u = home.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath:u.path) { candidates.append((u,category,explanation,classify(path).1)) }
        }
        var rules=CacheRules.rules
        do { rules += try CacheRules.browserCandidates(home:home) } catch { discoveryComplete=false; issues.append("Browser profile discovery: \(error.localizedDescription)");if let url=FileAccess.deniedURL(error) {denied.append(url.path)} }
        for rule in rules {
            let url=home.appendingPathComponent(rule.relative)
            if FileManager.default.fileExists(atPath:url.path) { candidates.append((url,rule.category,rule.explanation,rule.runningIDs)) }
        }
        let tmp = physicalURL(temporaryRoot)
        for u in list(tmp) {
            if let id = try? Identity.read(u), Date().timeIntervalSince1970 - Double(id.modified) > 7 * 86400 { candidates.append((u,"Temporary files","Temporary data untouched for at least seven days. Review because another process may still depend on it.",[])) }
        }
        let expanded=try ExpandedCleanCatalog.discover(home:home,systemRoot:systemRoot)
        issues += expanded.issues;denied += expanded.denied
        discoveryComplete = discoveryComplete && expanded.issues.isEmpty
        let targets=candidates.map { CleanTarget(url:$0.0,category:$0.1,explanation:$0.2,runningIDs:$0.3) } + expanded.targets
        let meter=CleanScanMeter(emit:activity)
        var results: [ReviewItem] = []; let deadline = Date().addingTimeInterval(90); var paths = Set<String>(); var nodes = 0
        for target in targets.sorted(by: { $0.url.path.count == $1.url.path.count ? $0.url.path < $1.url.path : $0.url.path.count < $1.url.path.count }) {
            let url=target.url,category=target.category,explanation=target.explanation,ids=target.runningIDs
            try Task.checkCancellation(); if Date() > deadline || nodes >= 250_000 { discoveryComplete=false; issues.append("Time or node budget reached; some catalog paths remain unvisited. Retry a smaller category or exclude large paths."); break }
            if exclusions.contains(where: { within(physicalURL(url).path,$0) }) || paths.contains(where:{within(physicalURL(url).path,$0)}) { continue }; paths.insert(physicalURL(url).path)
            progress(url.lastPathComponent,results.count);meter.publish(location:url.path)
            do {
                let measurement=try FileScanner.measure(url,limits:ScanLimits(nodes:min(100_000,250_000-nodes),seconds:min(15,deadline.timeIntervalSinceNow)),exclusions:exclusions,allocation:{identity,allocated,_ in meter.record(identity,bytes:allocated,location:url.path)})
                meter.publish(location:url.path)
                nodes += measurement.manifest.count
                guard measurement.files>0 || !measurement.complete || (["Trash","System Caches"].contains(category) && !measurement.manifest.isEmpty) else { continue }
                let relative=within(physicalURL(url).path,physicalURL(home).path) ? String(physicalURL(url).path.dropFirst(physicalURL(home).path.count+1)) : physicalURL(url).path
                let risk=target.risk ?? CacheRules.selectionRisk(category:category,relative:relative)
                let title=target.title ?? (url.path.contains("Application Support/") ? url.path.components(separatedBy:"Application Support/").last! : url.lastPathComponent)
                results.append(try ReviewItem(url:url,title:title,category:category,explanation:explanation,risk:risk,runningIDs:ids,measurement:measurement,readOnlyReason:target.readOnlyReason))
            } catch is CancellationError { throw CancellationError() } catch { discoveryComplete=false; issues.append("\(url.lastPathComponent): \(error.localizedDescription)");if let path=FileAccess.deniedURL(error,fallback:url) {denied.append(path.path)} }

        }
        return CleanReport(items:results,issues:issues,completeWithinCatalog:discoveryComplete && results.allSatisfy { $0.measurement.complete },deniedDiscoveryPaths:denied)
    }
    public static func dependencies(in root:URL,progress:@Sendable (String,Int)->Void={_,_ in}) throws -> [ReviewItem] { try dependencyReport(in:root,progress:progress).items }
    public static func dependencyReport(in root:URL,limits:ScanLimits=ScanLimits(nodes:15_000,seconds:60),progress:@Sendable (String,Int)->Void={_,_ in}) throws -> CleanReport {
        var stack:[(URL,Int)]=[(root,0)];var items:[ReviewItem]=[];var issues:[String]=[];var denied:[String]=[];var count=0;let end=ProcessInfo.processInfo.systemUptime+limits.seconds
        while let (url,depth)=stack.popLast() {
            try Task.checkCancellation();count += 1
            guard count<=limits.nodes,ProcessInfo.processInfo.systemUptime<end else { issues.append("Dependency discovery budget reached; results are partial. Choose a smaller project.");break }
            do {
                let id=try Identity.read(url);guard id.isDirectory,!id.isSymlink else { continue }
                if ["node_modules",".build","target"].contains(url.lastPathComponent) {
                    let m=try FileScanner.measure(url,limits:ScanLimits(seconds:min(10,max(0,end-ProcessInfo.processInfo.systemUptime))))
                    items.append(try ReviewItem(url:url,title:url.lastPathComponent,category:"Dependency folders",explanation:"Reinstall dependencies or rebuild this project after cleanup. Never selected automatically. Check your version control and deployment requirements.",risk:"High",confidence:"Folder name; manual review required",measurement:m))
                } else if depth<6 && ![".git","Library",".Trash"].contains(url.lastPathComponent) { stack += try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).map { ($0,depth+1) } }
                if count%128==0 { progress(url.lastPathComponent,count) }
            } catch is CancellationError { throw CancellationError() } catch { issues.append(url.lastPathComponent+": "+error.localizedDescription);if let path=FileAccess.deniedURL(error,fallback:url) {denied.append(path.path)} }
        }
        return CleanReport(items:items,issues:issues,completeWithinCatalog:issues.isEmpty && items.allSatisfy { $0.measurement.complete },deniedDiscoveryPaths:denied)
    }

}
public struct Tile: Sendable { public let index: Int; public let rect: CGRect }
public enum Treemap {
    /// Readable map areas: actual byte labels remain untouched. Clamp visual
    /// shares, redistributing the excess without overlap or tiny sliver tiles.
    public static func readableLayout(_ weights:[Double],in rect:CGRect,maximumShare:Double=0.55,minimumShare:Double=0.045)->[Tile] {
        let valid=weights.enumerated().filter {$0.element>0 && $0.element.isFinite}
        guard !valid.isEmpty else {return []}
        if valid.count==1 {
            let scale=sqrt(max(0.1,min(0.65,maximumShare.isFinite ? maximumShare:0.55)))
            let box=CGRect(x:rect.midX-rect.width*scale/2,y:rect.midY-rect.height*scale/2,width:rect.width*scale,height:rect.height*scale)
            return layout(weights,in:box)
        }
        let n=Double(valid.count),largest=valid.map(\.element).max()!
        let upper=max(1/n,min(1,maximumShare.isFinite ? maximumShare:0.55))
        let lower=max(0,min(1/n,minimumShare.isFinite ? minimumShare:0.045))
        let normalized=valid.map {$0.element/largest}
        var shares=Array(repeating:0.0,count:valid.count),pending=Array(valid.indices),remaining=1.0
        while !pending.isEmpty {
            let sum=pending.reduce(0) {$0+normalized[$1]}
            let proposed=pending.map {remaining*(sum>0 ? normalized[$0]/sum : 1/Double(pending.count))}
            // First remove upper-bound excess, then revisit lower bounds with
            // the enlarged budget. This keeps both bounds feasible.
            if let offset=proposed.firstIndex(where:{$0>upper+1e-12}) {
                let index=pending.remove(at:offset);shares[index]=upper;remaining-=upper;continue
            }
            if let offset=proposed.firstIndex(where:{$0<lower-1e-12}) {
                let index=pending.remove(at:offset);shares[index]=lower;remaining-=lower;continue
            }
            for (offset,index) in pending.enumerated() {shares[index]=proposed[offset]}
            break
        }
        var adjusted=Array(repeating:0.0,count:weights.count)
        for (offset,entry) in valid.enumerated() {adjusted[entry.offset]=shares[offset]}
        return layout(adjusted,in:rect)
    }
    /// Reserve a square corner for More items at every map depth and window size.
    public static func diskLayout(_ weights:[Double],remainder:Int?,in rect:CGRect)->[Tile] {
        guard let remainder,weights.indices.contains(remainder),weights[remainder]>0,
              rect.minX.isFinite,rect.minY.isFinite,rect.width.isFinite,rect.height.isFinite,
              rect.width>0,rect.height>0 else {return readableLayout(weights,in:rect)}
        let side=min(220,min(rect.width,rect.height)*0.40)
        let width=side,height=side
        let corner=CGRect(x:rect.maxX-width,y:rect.maxY-height,width:width,height:height)
        let items=weights.indices.filter {$0 != remainder && weights[$0]>0 && weights[$0].isFinite}
        guard !items.isEmpty else {return [Tile(index:remainder,rect:corner)]}
        let left=CGRect(x:rect.minX,y:rect.minY,width:rect.width-width,height:rect.height)
        let right=CGRect(x:corner.minX,y:rect.minY,width:width,height:rect.height-height)
        let fraction=right.width*right.height/(rect.width*rect.height)
        let rightCount=items.count==1 ? 0:min(items.count-1,max(items.count>=3 ? 2:1,Int((Double(items.count)*fraction).rounded())))
        let cut=items.count-rightCount
        func section(_ indices:ArraySlice<Int>,_ box:CGRect)->[Tile] {
            readableLayout(indices.map {weights[$0]},in:box).map {Tile(index:Array(indices)[$0.index],rect:$0.rect)}
        }
        return section(items[..<cut],left)+section(items[cut...],right)+[Tile(index:remainder,rect:corner)]
    }
    // Recursive balanced binary subdivision: two-dimensional, proportional, stable.
    public static func layout(_ weights: [Double], in rect: CGRect) -> [Tile] {
        guard rect.minX.isFinite,rect.minY.isFinite,rect.width.isFinite,rect.height.isFinite else {return []}
        let maximum=weights.filter {$0>0 && $0.isFinite}.max() ?? 1
        let values = weights.enumerated().filter { $0.element > 0 && $0.element.isFinite }.map { ($0.offset,$0.element/maximum) }
        var result: [Tile] = []
        func split(_ list: [(Int,Double)], _ box: CGRect) {
            guard !list.isEmpty,box.width > 0,box.height > 0 else { return }
            if list.count == 1 { result.append(Tile(index:list[0].0,rect:box)); return }
            let total = list.reduce(0) { $0+$1.1 }; var sum = 0.0; var cut = 1
            for i in 0..<(list.count-1) { sum += list[i].1; cut = i+1; if sum >= total/2 { break } }
            let ratio = sum/total
            if box.width >= box.height { let w = box.width*ratio; split(Array(list[..<cut]),CGRect(x:box.minX,y:box.minY,width:w,height:box.height)); split(Array(list[cut...]),CGRect(x:box.minX+w,y:box.minY,width:box.width-w,height:box.height)) }
            else { let h = box.height*ratio; split(Array(list[..<cut]),CGRect(x:box.minX,y:box.minY,width:box.width,height:h)); split(Array(list[cut...]),CGRect(x:box.minX,y:box.minY+h,width:box.width,height:box.height-h)) }
        }
        split(values,rect); return result
    }
}
