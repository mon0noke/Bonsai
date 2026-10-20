import Foundation
import BonsaiCore
import AppKit

final class ScanProbe:@unchecked Sendable {
    let lock=NSLock();private var current=0;private var peak=0;private var count=0
    func start() { lock.lock();current+=1;count+=1;peak=max(peak,current);lock.unlock() }
    func finish() { lock.lock();current-=1;lock.unlock() }
    var maximum:Int { lock.lock();defer { lock.unlock() };return peak }
    var calls:Int { lock.lock();defer { lock.unlock() };return count }
}
@main struct SoftwareStateChecks {
    @MainActor static func main() async throws {
        var failures=0,checks=0
        func check(_ value:Bool,_ label:String) { checks+=1;if !value { failures+=1 };print("\(value ? "PASS" : "FAIL") \(label)") }
        let root=URL(fileURLWithPath:NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("bonsai-software-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        func fixture(_ name:String) throws -> (InstalledApp,AppAssociationReport) {
            let app=root.appendingPathComponent(name+".app"),cache=root.appendingPathComponent(name+"-cache"),prefs=root.appendingPathComponent(name+"-prefs")
            for url in [app,cache,prefs] { try Data(repeating:1,count:4096).write(to:url) }
            let m=try FileScanner.measure(app)
            let installed=InstalledApp(url:physicalURL(app),name:name,bundleID:"fixture."+name,version:"1",measurement:m,lastUsed:nil,appStore:false)
            let files=try [(app,AppFileKind.application),(cache,.cache),(prefs,.preferences)].map { url,kind in AppAssociatedFile(item:try ReviewItem(url:url,title:kind.rawValue,category:"Fixture",explanation:"Disposable fixture",measurement:FileScanner.measure(url)),kind:kind) }
            return (installed,AppAssociationReport(appID:installed.id,files:files))
        }
        let fixtures=try ["Alpha","Beta","Gamma","Delta"].map(fixture);let apps=fixtures.map(\.0);let reports=Dictionary(uniqueKeysWithValues:fixtures.map { ($0.0.id,$0.1) });let policy=PathPolicy(roots:[root])
        let probe=ScanProbe()
        let store=SoftwareStore(defaults:nil,scanner:{ app,_,_ in probe.start();defer { probe.finish() };Thread.sleep(forTimeInterval:0.08);return reports[app.id]! })
        func settle(_ condition:()->Bool) async { for _ in 0..<200 { if condition() { return };try? await Task.sleep(nanoseconds:5_000_000) } }
        check(store.visible(apps.reversed(),query:"").map(\.name)==["Alpha","Beta","Delta","Gamma"],"Default ascending natural name sort")
        check(store.visible(apps,query:"",revision:1).count==4,"Revision-cached presentation starts complete")
        check(store.visible(apps,query:"Beta",revision:1).map(\.name)==["Beta"],"Search invalidates the cached presentation")
        check(store.visible(Array(apps.prefix(1)),query:"",revision:2).count==1,"New inventory revision replaces stale presentation")
        store.chooseSort(.name);check(store.visible(apps,query:"").first?.name=="Gamma","Repeated sort reverses actual presentation order")
        store.chooseSort(.size);check(!store.sort.ascending,"New numeric sort starts descending")
        check(store.visible(apps,query:"fixture.Beta").map(\.name)==["Beta"],"Search matches identifiers")
        for app in apps { store.toggleApp(app,inventory:apps,policy:policy) }
        check(store.inspectionsPending,"Selected inspections keep review pending")
        check(store.expanded.isEmpty,"Selecting apps keeps the list compact; disclosure is independent")
        await settle { store.plans.count==4 }
        check(store.plans.count==4 && probe.calls==4,"Queued inspections all complete")
        check(probe.maximum==2,"At most two scanners run concurrently")
        check(!store.inspectionsPending && store.selectedItems.count==8,"Only app and cache default selections reach review")
        let prefs=reports[apps[0].id]!.files[2]
        store.setFile(prefs.id,appID:apps[0].id,selected:true)
        check(store.selectedItems.count==9 && store.selectedBytes==store.selectedItems.reduce(0) { $0+$1.measurement.allocated },"Individual checkbox updates selected paths and totals")
        store.load(apps[0],inventory:apps,policy:policy,refresh:true)
        await settle { if case .loaded?=store.details[apps[0].id] { return true };return false }
        check(store.plans[apps[0].id]!.selected.contains(prefs.id),"Refresh retains an explicitly checked preference")
        store.setReviewGroup(apps[0].id,selected:false);check(!store.plans[apps[0].id]!.selected.contains(prefs.id),"Review group deselection leaves ready items")
        let preview=ItemOutcome(title:"Fixture",path:apps[0].id,status:"Preview",detail:"")
        store.consume([preview]);check(store.plans.count==4,"Preview preserves cached inspections")
        store.consume([ItemOutcome(title:"Fixture",path:prefs.id,status:"Trashed",detail:"")]);check(store.plans[apps[0].id]==nil && !store.chosen.contains(apps[0].id),"A removed file invalidates its app report")
        store.clear();check(store.chosen.isEmpty && store.selectedItems.isEmpty,"Clear selection clears every checked path")
        store.invalidate();check(store.plans.isEmpty && store.details.isEmpty && store.expanded.isEmpty,"Inventory invalidation clears old state")
        store.toggleExpanded(apps[0],inventory:apps,policy:policy)
        check(store.plans.isEmpty && store.chosen.isEmpty && store.expanded.isEmpty,"Unselected apps cannot expose inspection or queue disclosure scans")
        store.invalidate();store.toggleApp(apps[0],inventory:apps,policy:policy);store.clear()
        await settle { store.plans.count==1 };check(store.selectedItems.isEmpty && store.chosen.isEmpty,"Late inspection cannot restore a cleared selection")
        store.invalidate();store.toggleApp(apps[0],inventory:apps,policy:policy);store.cancelInspection(apps[0].id)
        await settle { if case .failed?=store.details[apps[0].id] { return true };return false }
        check(store.plans.isEmpty && !store.inspectionsPending,"Cancellation rejects even a scanner that ignores cancellation")
        store.invalidate();store.toggleApp(apps[1],inventory:apps,policy:policy);store.invalidate()
        try? await Task.sleep(nanoseconds:150_000_000)
        check(store.plans.isEmpty && store.details.isEmpty,"Old-generation scanner cannot publish into refreshed inventory")
        let blocked=SoftwareStore(defaults:nil,scanner:{ app,_,_ in let report=reports[app.id]!;return AppAssociationReport(appID:app.id,files:report.files.map { AppAssociatedFile(item:$0.item,kind:$0.kind,blockedReason:"Protected fixture") }) })
        blocked.toggleApp(apps[0],inventory:apps,policy:policy);await settle { blocked.plans.count==1 }
        blocked.setReviewGroup(apps[0].id,selected:true);check(blocked.selectedItems.isEmpty && blocked.chosen.contains(apps[0].id),"Selecting a protected app retains review access but cannot select unavailable files")
        blocked.activateApp(apps[0],inventory:apps,policy:policy)
        check(blocked.expanded.contains(apps[0].id) && blocked.selectedItems.isEmpty,"Protected app can expand explanations without authorizing removal")
        blocked.toggleApp(apps[0],inventory:apps,policy:policy);blocked.activateApp(apps[0],inventory:apps,policy:policy)
        check(blocked.chosen.contains(apps[0].id) && blocked.expanded.isEmpty && blocked.selectedItems.isEmpty,"Cached unavailable report stays compact and never creates removable paths")
        let duplicate=SoftwareStore(defaults:nil,scanner:{ app,_,_ in let own=reports[app.id]!;return AppAssociationReport(appID:app.id,files:[own.files[0],reports[apps[0].id]!.files[1]]) })
        for app in apps.prefix(2) { duplicate.toggleApp(app,inventory:apps,policy:policy) };await settle { duplicate.plans.count==2 }
        check(duplicate.selectedItems.count==3,"Shared candidate path is counted and reviewed once")
        let clicksProbe=ScanProbe()
        let disclosure=SoftwareStore(defaults:nil,scanner:{ app,_,_ in clicksProbe.start();defer {clicksProbe.finish()};Thread.sleep(forTimeInterval:0.02);return reports[app.id]! })
        disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.isEmpty,"First row click selects and stays collapsed")
        disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.contains(apps[0].id),"Second row click expands even while inspection is pending")
        disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.isEmpty,"Third row click collapses without deselecting")
        await settle { disclosure.plans.count==1 }
        check(clicksProbe.calls==1 && disclosure.selectedItems.count==2,"Repeated pending row clicks queue one scan and preserve default selection")
        disclosure.setFile(reports[apps[0].id]!.files[2].id,appID:apps[0].id,selected:true)
        let before=disclosure.selectedItems.map(\.id)
        disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.contains(apps[0].id) && disclosure.selectedItems.map(\.id)==before,"Selected row expansion preserves reviewed personal-data choices")
        disclosure.toggleExpanded(apps[0],inventory:apps,policy:policy)
        check(!disclosure.expanded.contains(apps[0].id) && disclosure.selectedItems.map(\.id)==before,"Summary collapse preserves selected files")
        disclosure.toggleExpanded(apps[0],inventory:apps,policy:policy)
        check(disclosure.expanded.contains(apps[0].id) && disclosure.selectedItems.map(\.id)==before,"Summary expansion preserves selection and cached report")
        for file in reports[apps[0].id]!.files {disclosure.setFile(file.id,appID:apps[0].id,selected:false)}
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.contains(apps[0].id) && disclosure.selectedItems.isEmpty,"Clearing individual paths keeps the app selected for review")
        disclosure.toggleApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.isEmpty && disclosure.expanded.isEmpty && disclosure.selectedItems.isEmpty,"Right checkbox deselects, collapses and clears checked paths")
        disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        check(disclosure.chosen.contains(apps[0].id) && disclosure.expanded.isEmpty && disclosure.selectedItems.count==2 && clicksProbe.calls==1,"Reselecting uses cached inspection with defaults and starts collapsed")
        disclosure.activateApp(apps[0],inventory:apps,policy:policy);disclosure.clear()
        check(disclosure.chosen.isEmpty && disclosure.expanded.isEmpty && disclosure.selectedItems.isEmpty,"Clear selection also hides all expanded app details")
        disclosure.activateApp(apps[0],inventory:apps,policy:policy);disclosure.activateApp(apps[0],inventory:apps,policy:policy)
        disclosure.consume([ItemOutcome(title:"Fixture",path:apps[0].id,status:"Trashed",detail:"")])
        check(disclosure.chosen.isEmpty && disclosure.expanded.isEmpty && disclosure.plans.isEmpty,"Removal invalidation clears selection and disclosure together")
        print("RESULT: \(checks) software-state checks, \(failures) failures; actual SoftwareStore.swift, disposable fixtures only")
        exit(failures==0 ? 0 : 1)
    }
}
