import Foundation

public struct ProcessApplication:Sendable {
    public let pid:Int32;public let url:URL;public let name:String
    public init(pid:Int32,url:URL,name:String) {self.pid=pid;self.url=url;self.name=name}
}
public struct ProcessGroup:Identifiable,Sendable {
    public let id:String;public let name:String;public let applicationURL:URL?;public let members:[ProcessSample];public let representative:ProcessSample
    public var pinKey:String {applicationURL == nil ? "process-name:\(representative.uid):\(name)" : id}
    public var memory:UInt64 {members.filter(\.metricsAvailable).reduce(0) {sum,p in let (v,overflow)=sum.addingReportingOverflow(p.memory);return overflow ? UInt64.max : v}}
    public var cpu:Double {members.filter(\.cpuAvailable).reduce(0) {$0+($1.cpu.isFinite ? max(0,$1.cpu) : 0)}}
    public var powerScore:Double? {sum(\.powerScore)}
    public var powerScoreComplete:Bool {members.allSatisfy {$0.powerScore != nil}}
    public var powerWatts:Double? {sum(\.powerWatts)}
    public var networkDownload:Double? {sum(\.networkDownload)}
    public var networkUpload:Double? {sum(\.networkUpload)}
    public var powerComplete:Bool {members.allSatisfy {$0.powerWatts != nil}}
    public var networkComplete:Bool {members.allSatisfy {$0.networkDownload != nil && $0.networkUpload != nil}}
    private func sum(_ key:KeyPath<ProcessSample,Double?>)->Double? {
        let values=members.compactMap {$0[keyPath:key]}.filter {$0.isFinite && $0>=0}
        return values.isEmpty ? nil:values.reduce(0,+)
    }
    public var memoryComplete:Bool {members.allSatisfy(\.metricsAvailable)}
    public var cpuComplete:Bool {members.allSatisfy {$0.cpuAvailable && $0.cpu.isFinite && $0.cpu>=0}}
    public var hasMemory:Bool {members.contains(where:\.metricsAvailable)}
    public var hasCPU:Bool {members.contains {$0.cpuAvailable && $0.cpu.isFinite && $0.cpu>=0}}
}
public enum ProcessSortKey:String,CaseIterable,Sendable {case name="Name",memory="Memory",cpu="CPU",power="Power",network="Network",pid="PID"}
public enum ProcessGrouping {
    /// Outer app bundle groups embedded helper apps. No name-only association or
    /// launchd-wide aggregation; unrelated users and app copies stay separate.
    public static func applicationURL(executable:String)->URL? {
        guard executable.hasPrefix("/") else {return nil}
        let parts=executable.split(separator:"/",omittingEmptySubsequences:true)
        guard !parts.contains(".."),!parts.contains("."),let index=parts.firstIndex(where:{$0.lowercased().hasSuffix(".app")}) else {return nil}
        return URL(fileURLWithPath:"/"+parts[...index].joined(separator:"/"))
    }
    public static func groups(_ samples:[ProcessSample],applications:[ProcessApplication]=[])->[ProcessGroup] {
        var byPID:[Int32:ProcessSample]=[:]
        for p in samples {
            if let old=byPID[p.pid],old.start>p.start || old.start==p.start && old.startMicro>=p.startMicro {continue}
            byPID[p.pid]=p
        }
        let unique=byPID.values.sorted {$0.id<$1.id}
        let apps=Dictionary(applications.map {($0.pid,$0)},uniquingKeysWith: {a,_ in a})
        var owners:[String:URL]=[:]
        for p in unique {
            if let url=applicationURL(executable:p.executable) {owners[p.id]=url}
            else if p.executable.isEmpty,let app=apps[p.pid],app.url.isFileURL,app.url.pathExtension.lowercased()=="app" {owners[p.id]=app.url.standardizedFileURL}
        }
        // An external executable may be an app child, but only measured same-UID
        // ancestry with an older parent qualifies. Depth/cycles bound the walk.
        for p in unique where owners[p.id]==nil {
            var child=p;var visited=Set<Int32>([p.pid])
            for _ in 0..<16 {
                guard let parent=byPID[child.parentPID],parent.pid>1,parent.uid==p.uid,visited.insert(parent.pid).inserted,
                    parent.start<child.start || parent.start==child.start && parent.startMicro<=child.startMicro else {break}
                if let url=owners[parent.id] {owners[p.id]=url;break};child=parent
            }
        }
        var buckets:[String:[ProcessSample]]=[:]
        for p in unique {let key=owners[p.id].map {"app:\(p.uid):"+$0.path} ?? "process:"+p.id;buckets[key,default:[]].append(p)}
        return buckets.map {key,members in
            let ordered=members.sorted {$0.start != $1.start ? $0.start<$1.start : $0.startMicro != $1.startMicro ? $0.startMicro<$1.startMicro : $0.pid<$1.pid}
            let url=owners[ordered[0].id]
            let main=ordered.first {p in guard let app=apps[p.pid],let url else {return false};return app.url.standardizedFileURL.path==url.path} ?? ordered[0]
            let name=url.map {apps[main.pid]?.name ?? $0.deletingPathExtension().lastPathComponent} ?? main.name
            return ProcessGroup(id:key,name:name,applicationURL:url,members:ordered,representative:main)
        }.sorted {$0.id<$1.id}
    }
    private static func compare(_ a:Double,_ b:Double)->ComparisonResult {a==b ? .orderedSame:a<b ? .orderedAscending:.orderedDescending}
    public static func presented(_ groups:[ProcessGroup],query:String,sort:ProcessSortKey,ascending:Bool,pinned:Set<String>)->[ProcessGroup] {
        let filtered=groups.filter {group in query.isEmpty || (group.name+" "+group.members.map {$0.name+" \($0.pid)"}.joined(separator:" ")).localizedCaseInsensitiveContains(query)}
        return filtered.sorted {a,b in
            let ap=pinned.contains(a.pinKey) || pinned.contains(a.name),bp=pinned.contains(b.pinKey) || pinned.contains(b.name)
            if ap != bp {return ap}
            if sort == .memory && a.hasMemory != b.hasMemory {return a.hasMemory}
            if sort == .cpu && a.hasCPU != b.hasCPU {return a.hasCPU}
            if sort == .power && (a.powerScore != nil) != (b.powerScore != nil) {return a.powerScore != nil}
            if sort == .network && (a.networkDownload != nil) != (b.networkDownload != nil) {return a.networkDownload != nil}
            let comparison:ComparisonResult
            switch sort {
            case .name:comparison=a.name.localizedStandardCompare(b.name)
            case .memory:comparison=a.memory==b.memory ? .orderedSame : a.memory<b.memory ? .orderedAscending : .orderedDescending
            case .cpu:comparison=a.cpu==b.cpu ? .orderedSame : a.cpu<b.cpu ? .orderedAscending : .orderedDescending
            case .power:comparison=compare(a.powerScore ?? 0,b.powerScore ?? 0)
            case .network:comparison=compare((a.networkDownload ?? 0)+(a.networkUpload ?? 0),(b.networkDownload ?? 0)+(b.networkUpload ?? 0))
            case .pid:comparison=a.representative.pid==b.representative.pid ? .orderedSame : a.representative.pid<b.representative.pid ? .orderedAscending : .orderedDescending
            }
            if comparison != .orderedSame {return ascending ? comparison == .orderedAscending : comparison == .orderedDescending}
            let name=a.name.localizedStandardCompare(b.name);return name == .orderedSame ? a.id<b.id : name == .orderedAscending
        }
    }
}
