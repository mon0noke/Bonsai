import Foundation

public enum DiskScope:String,Codable,Sendable {case folder,overview}
public struct DiskEntry:Identifiable,Codable,Sendable {
    public var id:String {url.path}
    public let url:URL;public let directory:Bool;public let measurement:Measurement
    public init(url:URL,directory:Bool,measurement:Measurement) {self.url=url;self.directory=directory;self.measurement=measurement}
    public var label:String {measurement.allocated==0 && !measurement.complete ? "Unknown size" : bytes(measurement.allocated)}
}
public struct DiskScan:Codable,Sendable {
    public let root:URL;public let entries:[DiskEntry];public let date:Date;public let issues:[String]
    public let scope:DiskScope;public let accountedTotal:UInt64;public let wasCancelled:Bool
    public var total:UInt64 {accountedTotal}
    public var complete:Bool {!wasCancelled && issues.isEmpty && entries.allSatisfy {$0.measurement.complete}}
    public var accessDeniedPaths:[String] {Array(Set(entries.flatMap {$0.measurement.accessDeniedPaths ?? []})).sorted()}
}
public struct DiskMapGroup:Identifiable,Sendable {
    public let entries:[DiskEntry]
    public let isRemainder:Bool
    public init(entries:[DiskEntry],isRemainder:Bool=false) {self.entries=entries;self.isRemainder=isRemainder}
    public var id:String {isRemainder ? "group:smaller" : entries[0].id}
    public var weight:UInt64 {entries.reduce(0) {saturatingAdd($0,$1.measurement.allocated)}}
    // Completeness is presented separately from the measured map weights.
    public var label:String {bytes(weight)}
    public var title:String {isRemainder ? "\(entries.count) item\(entries.count==1 ? "" : "s")" : entries[0].url.lastPathComponent}
    public static func make(_ entries:[DiskEntry],maximum:Int=9)->[DiskMapGroup] {
        let sorted=entries.filter {$0.measurement.allocated>0}.sorted { $0.measurement.allocated == $1.measurement.allocated ? $0.id<$1.id : $0.measurement.allocated>$1.measurement.allocated }
        guard sorted.count>max(0,maximum-1) else {return sorted.map {DiskMapGroup(entries:[$0])}}
        let count=max(0,maximum-1)
        return sorted.prefix(count).map {DiskMapGroup(entries:[$0])}+[DiskMapGroup(entries:Array(sorted.dropFirst(count)),isRemainder:true)]
    }
}
private func saturatingAdd(_ lhs:UInt64,_ rhs:UInt64)->UInt64 {let sum=lhs.addingReportingOverflow(rhs);return sum.overflow ? .max : sum.partialValue}
private struct DiskAccountKey:Hashable {let device:Int32;let inode:UInt64}
private final class DiskAccounting:@unchecked Sendable {
    let lock=NSLock();var seen=Set<DiskAccountKey>();var total:UInt64=0;var lastProgress:TimeInterval=0
    func add(_ identity:Identity,_ allocated:UInt64) {lock.lock();defer {lock.unlock()};if identity.links<=1 || seen.insert(DiskAccountKey(device:identity.device,inode:identity.inode)).inserted {total=saturatingAdd(total,allocated)}}
    func report()->Bool {lock.lock();defer {lock.unlock()};let now=ProcessInfo.processInfo.systemUptime;guard now-lastProgress>=0.125 else {return false};lastProgress=now;return true}
}
public actor DiskExplorer {
    private var cache:[String:DiskScan]=[:];private var recent:[String]=[]
    private let storage:DiskScanCache?
    public init(storage:DiskScanCache?=nil) {self.storage=storage}
    private var loaded=false
    private var revision=UUID()
    private func loadSaved() {
        guard !loaded else {return};loaded=true
        for scan in storage?.load() ?? [] {let key=scan.scope.rawValue+":"+scan.root.path;cache[key]=scan;touch(key)}
    }
    public func saved(_ requested:URL,scope:DiskScope = .folder)->DiskScan? {
        loadSaved();let key=scope.rawValue+":"+physicalURL(requested).path
        guard let scan=cache[key],Date().timeIntervalSince(scan.date)<7*86400 else {return nil}
        touch(key);return scan
    }
    public func invalidate() {revision=UUID();cache.removeAll();recent=[];loaded=true;storage?.remove()}
    private func remember(_ scan:DiskScan) {
        let key=scan.scope.rawValue+":"+scan.root.path;cache[key]=scan;touch(key)
        while recent.count>8 {cache.removeValue(forKey:recent.removeFirst())}
    }
    public static func overviewLocations(home:URL=FileManager.default.homeDirectoryForCurrentUser)->[URL] { [home,URL(fileURLWithPath:"/Applications"),URL(fileURLWithPath:"/Library"),URL(fileURLWithPath:"/opt")] }
    public func scan(_ requested:URL,refresh:Bool=false,scope:DiskScope = .folder,limits:ScanLimits=ScanLimits(nodes:2_000_000,seconds:600),progress:@escaping @Sendable (DiskEntry,Int,Int)->Void={_,_,_ in},activity:@escaping @Sendable (String,Int)->Void={_,_ in}) async throws -> DiskScan {
        try Task.checkCancellation()
        let root=physicalURL(requested),key=scope.rawValue+":"+root.path
        loadSaved()
        if !refresh,let value=cache[key],Date().timeIntervalSince(value.date)<7*86400 {touch(key);return value}
        let token=revision
        let worker=Task.detached(priority:.utility) {try Self.walk(root,scope:scope,limits:limits,progress:progress,activity:activity)}
        let (value,children)=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        // Invalidating during another operation must not repopulate the cache with
        // measurements taken before that filesystem change.
        if token==revision && !value.wasCancelled {
            for child in children {remember(child)}
            remember(value);storage?.save(recent.reversed().compactMap {cache[$0]})
        }
        return value
    }
    private nonisolated static func walk(_ root:URL,scope:DiskScope,limits:ScanLimits,progress:@escaping @Sendable (DiskEntry,Int,Int)->Void,activity:@escaping @Sendable (String,Int)->Void) throws -> (DiskScan,[DiskScan]) {
        try Task.checkCancellation()
        var childScans:[DiskScan]=[]
        let start=ProcessInfo.processInfo.systemUptime;var issues:[String]=[];var locations:[URL]
        if scope == .overview {locations=Self.overviewLocations().filter {FileManager.default.fileExists(atPath:$0.path)}}
        else {
            let identity=try Identity.read(root)
            guard identity.isDirectory,!identity.isSymlink else {throw BonsaiError.refused("Choose a real folder, rather than a symbolic link.")}
            let listing=try DirectoryListing.read(root,limit:100_000,expected:identity,deadlineUptime:start+min(30,limits.seconds))
            let priority=["Library","Downloads","Documents","Desktop","Movies","Music","Pictures","Applications"]
            locations=listing.urls.sorted {a,b in
                let left=priority.firstIndex(of:a.lastPathComponent) ?? (a.lastPathComponent.hasPrefix(".") ? 100 : 90)
                let right=priority.firstIndex(of:b.lastPathComponent) ?? (b.lastPathComponent.hasPrefix(".") ? 100 : 90)
                return left==right ? a.path<b.path : left<right
            }
            if !listing.complete {issues.append("Directory listing reached its 100,000-entry or time limit. Choose a smaller folder.")}
        }
        var entries:[DiskEntry]=[];var nodes=0;var cancelled=false;let accounting=DiskAccounting()
        var limitReached=false
        for (index,url) in locations.enumerated() {
            let remaining=limits.seconds-(ProcessInfo.processInfo.systemUptime-start)
            if Task.isCancelled || remaining<=0 || nodes>=limits.nodes {
                cancelled = cancelled || Task.isCancelled
                limitReached = limitReached || !Task.isCancelled
                var unmeasured=Measurement();unmeasured.complete=false
                unmeasured.issues=[cancelled ? "Not measured before the scan stopped." : "Not measured within this scan's limit. Open this folder to measure it separately."]
                if let identity=try? Identity.read(url) {unmeasured.manifest[physicalURL(url).path]=identity}
                entries.append(DiskEntry(url:url,directory:unmeasured.manifest[physicalURL(url).path]?.isDirectory ?? false,measurement:unmeasured))
                continue
            }
            let priorNodes=nodes
            var measurement:Measurement
            var children:[DiskEntry]=[];var childTotal:UInt64=0
            do {
                measurement=try DiskTreeScanner.measure(url,limits:ScanLimits(nodes:limits.nodes-nodes,seconds:remaining),allocation:{identity,size,_ in accounting.add(identity,size)},progress:{count in if accounting.report() {activity(url.lastPathComponent,priorNodes+count)}},collectChildren:true,children:{children=$0;childTotal=$1})
            } catch is CancellationError {cancelled=true;break}
            catch {measurement=Measurement();measurement.complete=false;measurement.issues=[error.localizedDescription];if FileAccess.isPermission(error) {measurement.accessDeniedPaths=[url.path]}}
            if measurement.complete,measurement.manifest[url.path]?.isDirectory==true,!children.isEmpty {
                childScans.append(DiskScan(root:url,entries:children.sorted {$0.measurement.allocated>$1.measurement.allocated},date:Date(),issues:[],scope:.folder,accountedTotal:childTotal,wasCancelled:false))
            }
            nodes += measurement.scannedNodes ?? measurement.manifest.count
            let entry=DiskEntry(url:url,directory:measurement.manifest[physicalURL(url).path]?.isDirectory ?? false,measurement:measurement)
            entries.append(entry);progress(entry,index+1,locations.count)
            if Task.isCancelled {cancelled=true}
        }
        if limitReached {issues.append("Scan limit reached. Unmeasured items are listed with unknown sizes; open a smaller folder to finish.")}
        if cancelled {issues.append("Stopped by you. Sizes shown are partial; refresh to complete.")}
        let value=DiskScan(root:root,entries:entries.sorted {$0.measurement.allocated == $1.measurement.allocated ? $0.id<$1.id : $0.measurement.allocated>$1.measurement.allocated},date:Date(),issues:issues,scope:scope,accountedTotal:accounting.total,wasCancelled:cancelled)
        return (value,childScans)
    }
    private func touch(_ key:String) {recent.removeAll {$0==key};recent.append(key)}
}
