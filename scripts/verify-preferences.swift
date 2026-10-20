import Foundation
import AppKit
import SwiftUI
import BonsaiCore

@main struct VerifyPreferences {
    @MainActor static func main() throws {
        var checks=0;var failures=0
        func check(_ value:Bool,_ name:String) {checks+=1;if !value {failures+=1};print("\(value ? "PASS":"FAIL") \(name)")}
        let suite="bonsai-alert-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        var sent:[(String,String)]=[]
        func service()->PreferenceAlerts {PreferenceAlerts(defaults:defaults,sender:{sent.append(($0,$1))})}
        let alerts=service(),start=Calendar.current.startOfDay(for:Date()).addingTimeInterval(3600)
        var sample=TelemetrySnapshot();sample.cpu=99;sample.gpu=GPUSample(utilization:98,cores:8,model:"Fixture",state:"Fixture");sample.pressure="Normal";sample.thermal="Nominal"
        func tick(_ seconds:Int,_ active:Bool=true) {alerts.observe(sample,accessories:nil,now:start.addingTimeInterval(Double(seconds)),userActive:active)}
        tick(0);tick(10);tick(20)
        check(sent.isEmpty,"Short CPU/GPU spikes stay quiet")
        for s in stride(from:30,through:60,by:10) {tick(s)}
        check(sent.count==1 && sent.last!.0=="High CPU Pressure : 99%\nHigh GPU Pressure : 98%" && sent.last!.1.isEmpty,"Sustained 95% CPU/GPU produces one grouped alert")
        for s in stride(from:70,through:120,by:10) {tick(s)}
        check(sent.count==1,"Continuous high usage never repeats")
        sample.cpu=50;sample.gpu=GPUSample(utilization:30,cores:8,model:"Fixture",state:"Fixture")
        for s in stride(from:130,through:170,by:10) {tick(s)}
        sample.cpu=99
        for s in stride(from:180,through:250,by:10) {tick(s)}
        check(sent.count==1,"Recovery and a second spike respect the 30-minute cooldown")
        sample.cpu=20;sample.pressure="Warning";sample.memoryUsed=99;sample.memoryTotal=100
        for s in stride(from:260,through:330,by:10) {tick(s)}
        check(sent.count==1,"High RAM occupancy and Warning alone stay quiet")
        sample.pressure="Critical"
        for s in stride(from:340,through:370,by:10) {tick(s)}
        check(sent.count==2 && sent.last!.0=="High RAM Pressure : 99%" && sent.last!.1.isEmpty,"Critical macOS RAM pressure alerts after 30 seconds")
        sample.pressure="Normal";sample.thermal="Critical"
        for s in stride(from:380,through:440,by:10) {tick(s)}
        check(sent.count==3 && sent.last!.0=="High Thermal Pressure : Critical" && sent.last!.1.isEmpty,"Sustained thermal pressure alerts")
        defaults.set(false,forKey:"resourceAlerts")
        let count=sent.count
        for s in stride(from:450,through:550,by:10) {tick(s)}
        check(sent.count==count,"Resource opt-out suppresses all pressure notifications")
        defaults.set(true,forKey:"privacyAlerts");defaults.set(true,forKey:"awakeReminders");defaults.set(true,forKey:"diskAlerts")
        sample.diskFree=1;sample.diskTotal=100;tick(560)
        check(sent.count==count,"Legacy privacy, Awake, and low-disk switches cannot emit old alerts")
        defaults.set(true,forKey:"resourceAlerts")
        let sleepService=service();sample.thermal="Nominal";sample.pressure="Normal";sample.cpu=99
        sleepService.observe(sample,accessories:nil,now:start.addingTimeInterval(4000))
        sleepService.observe(sample,accessories:nil,now:start.addingTimeInterval(8000))
        check(sent.count==count,"Sleep or missing samples cannot count as sustained load")
        for s in stride(from:8010,through:8100,by:10) {sleepService.observe(sample,accessories:nil,now:start.addingTimeInterval(Double(s)),userActive:false)}
        check(sent.count==count,"Inactive Mac cannot emit pressure alerts")
        defaults.set(true,forKey:"bluetoothAlerts")
        alerts.observe(sample,accessories:[("Fixture Mouse",20)],now:start.addingTimeInterval(9000),userActive:false)
        check(sent.count==count+1 && sent.last!.1.contains("20%"),"Exactly 20% battery triggers an alert")
        alerts.observe(sample,accessories:[("Fixture Mouse",19)],now:start.addingTimeInterval(9010),userActive:false)
        alerts.observe(sample,accessories:[],now:start.addingTimeInterval(9020),userActive:false)
        alerts.observe(sample,accessories:[("Fixture Mouse",18)],now:start.addingTimeInterval(9030),userActive:false)
        check(sent.count==count+1,"Low battery samples and reconnects do not repeat")
        let restarted=service()
        restarted.observe(sample,accessories:[("Fixture Mouse",18)],now:start.addingTimeInterval(9040),userActive:false)
        check(sent.count==count+1,"Battery cooldown survives a restart")
        alerts.observe(sample,accessories:[("Fixture Mouse",30)],now:start.addingTimeInterval(9050),userActive:false)
        alerts.observe(sample,accessories:[("Fixture Mouse",20)],now:start.addingTimeInterval(9060),userActive:false)
        check(sent.count==count+2,"Recharging above 25% rearms the next discharge alert")
        alerts.observe(sample,accessories:[("Invalid",-1),("Invalid2",101)],now:start.addingTimeInterval(9070),userActive:false)
        check(sent.count==count+2,"Unavailable or invalid battery readings never alert")
        let beforeDaily=sent.count
        alerts.dailyUpdates(count:4,checkedAt:start,now:start,userActive:false)
        check(sent.count==beforeDaily,"Update summary waits while the Mac is inactive")
        alerts.dailyUpdates(count:4,checkedAt:start.addingTimeInterval(-86400),now:start,userActive:true)
        check(sent.count==beforeDaily,"Yesterday’s update cache cannot produce today’s summary")
        alerts.dailyUpdates(count:4,checkedAt:start,now:start,userActive:true)
        check(sent.count==beforeDaily+1 && sent.last!.0=="4 app updates available" && sent.last!.1.isEmpty,"Active user receives checked update count")
        alerts.dailyUpdates(count:7,checkedAt:start,now:start.addingTimeInterval(100),userActive:true)
        service().dailyUpdates(count:7,checkedAt:start,now:start.addingTimeInterval(200),userActive:true)
        check(sent.count==beforeDaily+1,"Daily summary is once per day across checks and restarts")
        let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:start)!
        alerts.dailyUpdates(count:0,checkedAt:tomorrow,now:tomorrow,userActive:true)
        check(sent.count==beforeDaily+2 && sent.last!.0=="0 app updates available" && sent.last!.1.isEmpty,"Next active day receives a fresh summary including zero updates")
        defaults.set(false,forKey:"dailyUpdateAlerts")
        check(!alerts.needsDailyUpdates(now:tomorrow.addingTimeInterval(86400)),"Daily summary opt-out is respected")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("BonsaiAlertFixture-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let app=root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at:app,withIntermediateDirectories:true)
        try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"app.bonsai.alert.fixture","CFBundleName":"Fixture","CFBundlePackageType":"APPL"],format:.xml,options:0).write(to:app.appendingPathComponent("Info.plist"))
        let notices=try TrashAppMonitor.inspect(root)
        check(notices.count==1,"Disposable Trash observer fixture is valid")
        let beforeTrash=sent.count
        alerts.observeTrash(notices)
        check(sent.count==beforeTrash,"First Trash snapshot establishes a quiet baseline")
        alerts.observeTrash([]);alerts.observeTrash(notices)
        check(sent.count==beforeTrash+1 && sent.last!.0=="Fixture removed to Trash. Review leftovers." && sent.last!.1.isEmpty,"New app in Trash produces a leftovers notification")
        alerts.observeTrash(notices);service().observeTrash(notices)
        check(sent.count==beforeTrash+1,"Existing Trash apps do not repeat across polls or restarts")
        defaults.set(false,forKey:"leftoverAlerts");alerts.observeTrash([]);alerts.observeTrash(notices)
        check(sent.count==beforeTrash+1,"Leftovers notification opt-out is respected")
        defaults.set(true,forKey:"leftoverAlerts");alerts.observeTrash([])
        let beforeUninstall=sent.count
        alerts.uninstalledApps([(name:"Fixture",recovery:notices[0].url.path)])
        check(sent.count==beforeUninstall+1,"Bonsai uninstall notifies even if the optional Trash watcher is off")
        alerts.observeTrash(notices)
        check(sent.count==beforeUninstall+1,"Trash watcher cannot duplicate a Bonsai uninstall notification")
        check(PreferenceAlerts.pressureText("GPU",percent:90)=="High GPU Pressure : 90%","GPU wording matches the requested example exactly")
        check(PreferenceAlerts.pressureText("GPU",percent:nil)=="High GPU Pressure","Missing readings never invent a percentage")
        check(PreferenceAlerts.leftoversText("Example app")=="Example app removed to Trash. Review leftovers.","Leftovers wording matches the requested example exactly")
        let masterSuite="bonsai-master-alert-tests-"+UUID().uuidString,masterDefaults=UserDefaults(suiteName:masterSuite)!
        defer {masterDefaults.removePersistentDomain(forName:masterSuite)}
        var masterSent:[String]=[]
        let master=PreferenceAlerts(defaults:masterDefaults,sender:{title,_ in masterSent.append(title)})
        master.setNotificationsEnabled(false)
        var low=TelemetrySnapshot();low.cpu=99;low.pressure="Critical";low.thermal="Critical";low.diskTotal=100*1024*1024*1024;low.diskFree=1024*1024*1024
        for s in stride(from:0,through:90,by:10) {master.observe(low,accessories:[("Muted Mouse",10)],now:start.addingTimeInterval(Double(s)))}
        master.observeTrash([]);master.observeTrash(notices)
        master.uninstalledApps([(name:"Muted app",recovery:nil)])
        master.dailyUpdates(count:8,checkedAt:start,now:start,userActive:true)
        check(masterSent.isEmpty && !master.needsDailyUpdates(now:start),"Master off suppresses pressure, battery, storage, leftovers, uninstall and update notifications")
        check(masterDefaults.bool(forKey:"resourceAlerts") && masterDefaults.bool(forKey:"leftoverAlerts"),"Master switch preserves category preferences")
        master.setNotificationsEnabled(true)
        master.observe(low,accessories:[("Muted Mouse",10)],now:start.addingTimeInterval(100))
        check(masterSent.count==1,"Master re-enable allows a low battery that was first observed while muted")
        masterDefaults.set(false,forKey:"resourceAlerts");masterDefaults.set(false,forKey:"bluetoothAlerts")
        let diskStart=masterSent.count
        for s in stride(from:110,through:150,by:10) {master.observe(low,accessories:nil,now:start.addingTimeInterval(Double(s)))}
        check(masterSent.count==diskStart,"Low disk space waits for 60 seconds of active samples")
        master.observe(low,accessories:nil,now:start.addingTimeInterval(160))
        check(masterSent.count==diskStart+1 && masterSent.last!.hasPrefix("Low Disk Space : "),"Sustained low disk space sends a concise notification")
        master.observe(low,accessories:nil,now:start.addingTimeInterval(170))
        check(masterSent.count==diskStart+1,"Low disk space does not repeat continuously")
        let restartedMaster=PreferenceAlerts(defaults:masterDefaults,sender:{title,_ in masterSent.append(title)})
        for s in stride(from:180,through:260,by:10) {restartedMaster.observe(low,accessories:nil,now:start.addingTimeInterval(Double(s)))}
        check(masterSent.count==diskStart+1,"Storage cooldown survives an app restart")
        masterDefaults.set(false,forKey:"lowDiskAlerts")
        for s in stride(from:86500,through:86580,by:10) {master.observe(low,accessories:nil,now:start.addingTimeInterval(Double(s)))}
        check(masterSent.count==diskStart+1,"Low disk category opt-out suppresses the next daily alert")
        masterDefaults.set(true,forKey:"lowDiskAlerts")
        low.diskFree=30*1024*1024*1024
        for s in stride(from:86600,through:86680,by:10) {master.observe(low,accessories:nil,now:start.addingTimeInterval(Double(s)))}
        check(masterSent.count==diskStart+1,"Healthy available storage stays quiet")
        low.diskTotal=0;low.diskFree=0
        for s in stride(from:86700,through:86780,by:10) {master.observe(low,accessories:nil,now:start.addingTimeInterval(Double(s)))}
        check(masterSent.count==diskStart+1,"Unavailable storage readings cannot trigger an alert")
        print("RESULT: \(checks) notification checks, \(failures) failures; isolated preferences, injected time and notification delivery")
        exit(failures==0 ? 0:1)
    }
}
