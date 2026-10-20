import AppKit
import Foundation
import BonsaiCore

@main struct MappingChecks {
    @MainActor static func main() async throws {
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ name:String) {checks+=1;if !value {fatalError("FAIL: "+name)};print("PASS "+name)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("bonsai-background-fixture-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let first=root.appendingPathComponent("First"),second=root.appendingPathComponent("Second")
        for directory in [first,second] {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try Data(repeating:3,count:8192).write(to:directory.appendingPathComponent("data"))}
        let explorer=DiskExplorer(),firstResult=try await explorer.scan(first),secondResult=try await explorer.scan(second)
        let model=AppModel(startServices:false,diskScanOverride:{url,_,_ in
            // Deliberately ignore cancellation to verify generation rejection.
            try? await Task.sleep(nanoseconds:url.lastPathComponent=="First" ? 250_000_000:80_000_000)
            return url.lastPathComponent=="First" ? firstResult:secondResult
        })
        defer {model.shutdown()}
        model.page = .analyze;model.scanDisk(root:first)
        check(model.diskScanning && !model.busy && model.operationKind.isEmpty,"Disk scan has independent busy and progress state")
        model.page = .optimize
        model.begin("Maintenance fixture",kind:"maintenance") {_ in try? await Task.sleep(nanoseconds:160_000_000)}
        check(model.busy && model.diskScanning && model.operationKind=="maintenance","Foreground maintenance can start while disk mapping runs")
        check(model.canNavigateDisk,"Disk navigation remains available during foreground work")
        model.cancelDisk()
        check(model.busy && model.operationKind=="maintenance","Cancelling disk mapping does not cancel maintenance")
        model.scanDisk(root:second)
        check(model.diskScanning && model.busy && model.diskRoot==second,"New scan can replace old scan during foreground work")
        try await Task.sleep(nanoseconds:350_000_000)
        check(model.disk?.root==physicalURL(second) && !model.diskScanning,"Late obsolete result cannot replace new map")
        check(!model.busy && model.progress.isEmpty,"Foreground completion resets only foreground state")
        model.scanDisk(root:first);model.page = .clean
        model.begin("Clean fixture",kind:"clean") {_ in while !Task.isCancelled {try? await Task.sleep(nanoseconds:10_000_000)}}
        check(model.busy && model.diskScanning && model.operationKind=="clean","Foreground cleaning can start during disk mapping")
        model.cancel()
        try await Task.sleep(nanoseconds:30_000_000)
        check(!model.busy && model.diskScanning,"Clean-page cancellation leaves disk scan running")
        model.page = .analyze;model.cancel()
        try await Task.sleep(nanoseconds:300_000_000)
        check(!model.busy && !model.diskScanning,"Analyze-page cancellation stops only mapping")
        print("RESULT: \(checks) background mapping lifecycle checks, zero failures; disposable data and injected operations only")
    }
}
