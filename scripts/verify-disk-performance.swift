import Foundation
import BonsaiCore
@main struct DiskPerformance {
    static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-performance-"+UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer {try? FileManager.default.removeItem(at:root)}
        for group in 0..<30 {
            let directory=root.appendingPathComponent("group-\(group)");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
            for i in 0..<400 {try Data(repeating:42,count:32).write(to:directory.appendingPathComponent("file-\(i)"))}
        }
        let file=root.appendingPathComponent("group-0/file-0")
        try FileManager.default.linkItem(at:file,to:root.appendingPathComponent("hardlink"))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("external-link"),withDestinationURL:URL(fileURLWithPath:"/Applications"))
        let limits=ScanLimits(nodes:100_000,seconds:60)
        var legacy:[Double]=[],fast:[Double]=[]
        var measured:UInt64=0
        for _ in 0..<3 {
            var start=ProcessInfo.processInfo.systemUptime
            let reference=try FileScanner.measure(root,limits:limits,diskAccounting:true)
            legacy.append(ProcessInfo.processInfo.systemUptime-start)
            start=ProcessInfo.processInfo.systemUptime
            let result=try DiskTreeScanner.measure(root,limits:limits)
            fast.append(ProcessInfo.processInfo.systemUptime-start)
            precondition(reference.complete && result.complete && reference.allocated==result.allocated && reference.logical==result.logical && reference.files==result.files)
            measured=result.allocated
        }
        let storage=DiskScanCache(directory:root.appendingPathComponent("private-cache"))
        let explorer=DiskExplorer(storage:storage)
        let initialStart=ProcessInfo.processInfo.systemUptime
        let disk=try await explorer.scan(root,refresh:true)
        let initialSeconds=ProcessInfo.processInfo.systemUptime-initialStart
        let start=ProcessInfo.processInfo.systemUptime
        let cached=try await explorer.scan(root)
        let cachedSeconds=ProcessInfo.processInfo.systemUptime-start
        guard disk.date==cached.date && disk.complete else {throw BonsaiError.unavailable("Disk fixture: "+disk.issues.joined(separator:"; ")+disk.entries.filter {!$0.measurement.complete}.map {$0.url.lastPathComponent+": "+$0.measurement.issues.joined(separator:"; ")}.joined(separator:" | "))}
        let restartStart=ProcessInfo.processInfo.systemUptime
        let restarted=try await DiskExplorer(storage:storage).scan(root)
        let restartedSeconds=ProcessInfo.processInfo.systemUptime-restartStart
        precondition(restarted.date==disk.date)
        let childStart=ProcessInfo.processInfo.systemUptime
        let group=try await explorer.scan(root.appendingPathComponent("group-9"))
        let childSeconds=ProcessInfo.processInfo.systemUptime-childStart
        precondition(group.entries.count==400)
        let old=legacy.sorted()[1],new=fast.sorted()[1]
        let object:[String:Any]=["fixtureFiles":12000,"allocationMatches":true,"allocatedBytes":measured,"oldSeconds":legacy,"newSeconds":fast,"medianSpeedup":old/new,"cachedNavigationSeconds":cachedSeconds,"initialExplorerSeconds":initialSeconds,"savedMapReloadSeconds":restartedSeconds,"childNavigationSeconds":childSeconds,"liveGPU":GPUTelemetry.sample().utilization.map {NSNumber(value:$0)} ?? NSNull()]
        print(String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
