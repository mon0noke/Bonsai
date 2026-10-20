import Foundation
import BonsaiCore

private actor Probe {
    var count=0
    func visit() {count+=1}
    func calls()->Int {count}
}
@main struct SoftwareServicesChecks {
    @MainActor static func main() async throws {
        var checks=0,failures=0
        func check(_ value:Bool,_ label:String) {checks+=1;if !value {failures+=1};print("\(value ? "PASS" : "FAIL") \(label)")}
        let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("bonsai-update-fixtures-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let app=InstalledApp(url:root.appendingPathComponent("Fixture.app"),name:"Fixture",bundleID:"app.bonsai.fixture",version:"1",measurement:Measurement(),lastUsed:nil,appStore:false)
        let update=SoftwareUpdate(id:"feed:fixture",name:"Fixture",installed:"1",available:"2",source:"Appcast",information:"Fixture",applicationURL:app.url)
        let report=MetadataCheckReport(updates:[update],notes:["One fixture source"],checked:1)
        func settle(_ condition:()->Bool) async {for _ in 0..<200 {if condition() {return};try? await Task.sleep(nanoseconds:5_000_000)}}
        let probe=Probe()
        let store=SoftwareUpdatesStore(defaults:nil,check:{_,progress in await probe.visit();await progress(report);try await Task.sleep(nanoseconds:20_000_000);return report})
        check(store.automatic,"Automatic metadata checks are enabled for the requested behavior")
        store.enter(apps:[app]);check(store.checking,"Opening Updates begins a check without a button")
        store.enter(apps:[app]);store.refresh(apps:[app]);await settle {!store.checking}
        let calls=await probe.calls();check(calls==1,"Concurrent visits and refreshes share one active check")
        check(store.items.map(\.id)==[update.id] && store.date != nil,"Completion publishes versioned results and freshness")
        check(store.inspected==1 && store.note.contains("fixture"),"Check details keep source coverage")
        store.enter(apps:[app]);try? await Task.sleep(nanoseconds:20_000_000)
        let reused=await probe.calls();check(reused==1,"Recent inventory-matching results do not refetch")
        store.refresh(apps:[app]);await settle {!store.checking};let refreshed=await probe.calls();check(refreshed==2,"Explicit refresh bypasses cache freshness")
        store.automatic=false;store.enter(apps:[app]);try? await Task.sleep(nanoseconds:10_000_000)
        let optout=await probe.calls();check(optout==2,"Opt-out prevents automatic traffic")
        store.refresh(apps:[app]);await settle {!store.checking};let manual=await probe.calls();check(manual==3,"Manual refresh is available after opting out")
        check(SoftwareUpdatesStore.deduplicate([update,update]).count==1,"Duplicate source IDs cannot produce duplicate rows")
        let encoded=try JSONEncoder().encode(SoftwareUpdatesStore.Snapshot(items:[update],note:"Fixture",date:Date(),fingerprint:[app.id]))
        let decoded=try JSONDecoder().decode(SoftwareUpdatesStore.Snapshot.self,from:encoded)
        check(decoded.items[0].available=="2" && decoded.items[0].applicationURL==app.url,"Local cache round-trips versions and source handoffs")
        let incremental=SoftwareUpdatesStore(defaults:nil,check:{_,progress in await progress(report);try await Task.sleep(nanoseconds:60_000_000);return report})
        incremental.enter(apps:[app]);await settle {!incremental.items.isEmpty}
        check(incremental.checking && incremental.items[0].id==update.id,"Updates appear incrementally before the whole pass finishes")
        incremental.cancel();check(!incremental.checking && incremental.failure?.contains("cancelled")==true,"Cancellation immediately releases the screen")
        try? await Task.sleep(nanoseconds:80_000_000);check(incremental.date==nil,"Cancelled work cannot publish completed freshness")
        let late=SoftwareUpdatesStore(defaults:nil,check:{_,progress in try? await Task.sleep(nanoseconds:40_000_000);await progress(report);return report})
        late.enter(apps:[app]);late.cancel();try? await Task.sleep(nanoseconds:80_000_000)
        check(late.items.isEmpty && late.date==nil,"Generation rejects a worker that ignores cancellation")
        let failed=SoftwareUpdatesStore(defaults:nil,check:{_,progress in await progress(report);throw BonsaiError.unavailable("Offline fixture")})
        failed.enter(apps:[app]);await settle {!failed.checking}
        check(failed.failure=="Offline fixture" && failed.date==nil,"Failure is actionable and cannot claim a completed check")
        check(failed.items.count==1,"Partial useful results survive a later source failure")
        let installStore=SoftwareUpdatesStore(defaults:nil,check:{_,_ in report});installStore.enter(apps:[app]);await settle {!installStore.checking}
        installStore.installed(update.id);check(installStore.items.isEmpty && installStore.date==nil,"Verified installation invalidates cached availability")
        let refreshProbe=Probe()
        let stale=SoftwareUpdatesStore(defaults:nil,check:{_,progress in
            await refreshProbe.visit();let count=await refreshProbe.calls()
            if count==1 {return report}
            await progress(MetadataCheckReport(updates:[],notes:["Checked, no update"],checked:1,appStates:[app.id:"No update detected"]))
            try await Task.sleep(nanoseconds:30_000_000)
            return MetadataCheckReport(updates:[],notes:[],checked:1,appStates:[app.id:"No update detected"])
        })
        stale.enter(apps:[app]);await settle {!stale.checking};check(stale.items.count==1,"First pass saves fixture availability")
        stale.refresh(apps:[app]);await settle {stale.appStates[app.id] != nil}
        check(stale.checking && stale.items.isEmpty,"Fresh incremental pass clears an update that is no longer available")
        await settle {!stale.checking};check(stale.items.isEmpty && stale.appStates[app.id]=="No update detected","Completion keeps current per-app availability without stale rows")
        store.queueInstallations([update])
        check(store.installations[update.id]?.phase == .queued,"Update All keeps progress beside the queued app")
        store.installationProgress(.download(received:50,total:100),for:update.id)
        check(store.installations[update.id]?.fraction == 0.5,"Download bytes drive the row percentage")
        store.installationProgress(.download(received:20,total:100),for:update.id)
        check(store.installations[update.id]?.fraction == 0.5,"Delayed download callbacks cannot move the bar backwards")
        store.installationProgress(SoftwareUpdateProgress(.installing),for:update.id)
        store.installationProgress(.download(received:90,total:100),for:update.id)
        check(store.installations[update.id]?.phase == .installing && store.installations[update.id]?.fraction == nil,"Installing uses honest activity and rejects stale download callbacks")
        store.finishInstallation(update.id)
        store.installationProgress(.download(received:100,total:100),for:update.id)
        check(store.installations.isEmpty,"Completed and cancelled rows cannot be revived by a late callback")
        check(SoftwareUpdateProgress.download(received:10,total:-1).fraction == nil,"Unknown download size never invents a percentage")
        check(SoftwareUpdateProgress.download(received:200,total:100).fraction == 1 && SoftwareUpdateProgress(.downloading,fraction:.nan).fraction == nil,"Progress handles oversized and unavailable readings")
        store.queueInstallations([update]);store.clearInstallations()
        check(store.installations.isEmpty,"Batch completion or cancellation clears queued progress")
        let failedUpdate=ItemOutcome(title:"Fixture",path:update.id,status:"Failed",detail:"Publisher signature does not match the installed app. Nothing was replaced.")
        store.recordOutcome(failedUpdate)
        check(store.issues[update.id]=="Publisher verification failed.","Failed updates get a short hover reason")
        store.queueInstallations([update]);check(store.issues[update.id]==nil,"Retry clears the old warning icon")
        store.restoreUpdateOutcomes([AuditEntry(operation:"Update all",outcomes:[failedUpdate])])
        check(store.issues[update.id] != nil,"Recent update failures can be restored after relaunch")
        store.recordOutcome(ItemOutcome(title:"Fixture",path:update.id,status:"Updated",detail:"Verified"))
        check(store.issues[update.id]==nil,"Successful update clears its warning icon")
        let running=ItemOutcome(title:"Fixture",path:update.id,status:"Needs attention",detail:"Quit this application before replacing it.")
        check(SoftwareUpdatesStore.shortFailure(running)=="Quit the app, then retry.","Running app warning stays short")
        let verbose=ItemOutcome(title:"Fixture",path:update.id,status:"Failed",detail:String(repeating:"Technical log line /Users/example ",count:100))
        check((SoftwareUpdatesStore.shortFailure(verbose)?.count ?? 999)<70,"Raw technical logs never leak into a long tooltip")
        let package=SoftwareUpdate(id:"fixture-pkg",name:"Fixture package",installed:"1",available:"2",source:"Homebrew package",information:"",downloadURL:URL(string:"https://publisher.example/Installer.pkg"),downloadSHA256:String(repeating:"a",count:64))
        check(package.canPrepareInstaller && !package.canInstall,"Package updates require explicit download and installer actions, never automatic Update All installation")
        let noChecksum=SoftwareUpdate(id:"fixture-pkg",name:"Fixture package",installed:"1",available:"2",source:"Homebrew package",information:"",downloadURL:URL(string:"https://publisher.example/Installer.pkg"))
        check(!noChecksum.canPrepareInstaller,"Unsigned catalog metadata cannot enable package downloads")
        check(PackageReceipt.version("../../etc/passwd")==nil,"Receipt lookup refuses paths and regular expressions")
        check(DirectUpdates.recoveryTeam("ch.protonvpn.mac")=="J6S6Q257EK" && DirectUpdates.recoveryTeam("com.todesktop.241012ess7yxs0e")=="6FXBT88W8J" && DirectUpdates.recoveryTeam("unlisted.app")==nil,"Invalid-install repair is limited to two independently verified publishers")
        let installer=ItemOutcome(title:"Fixture",path:update.id,status:"Installer opened",detail:"Finish installation")
        check(SoftwareUpdatesStore.shortFailure(installer)=="Finish the macOS installer, then refresh.","Installer handoff stays explicit and is not reported as an installed update")
        let missingScript=ItemOutcome(title:"FUSE-T",path:"fuse-t",status:"Failed",detail:"Running uninstall script /Library/Application Support/fuse-t/uninstall.sh\nError: uninstall script does not exist.")
        check(SoftwareUpdatesStore.shortFailure(missingScript)=="Homebrew setup is incomplete. Use the installer.","Homebrew Running uninstall logs cannot be mistaken for a running app")
        print("RESULT: \(checks) checks, \(failures) failures")
        if failures>0 {exit(1)}
    }
}
