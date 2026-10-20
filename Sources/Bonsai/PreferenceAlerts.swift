import Foundation
import AppKit
import UserNotifications
import IOKit
import BonsaiCore

enum ConnectedAccessories {
    static func read()->[(String,Int)] {
        // Connected HID devices expose battery data only when supported by their driver.
        var values:[String:Int]=[:]
        for serviceClass in ["IOHIDDevice","AppleDeviceManagementHIDEventService"] {
            var iterator:io_iterator_t=0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching(serviceClass),&iterator)==KERN_SUCCESS else {continue}
            defer {IOObjectRelease(iterator)}
            var count=0
            while count<256 {
                let service=IOIteratorNext(iterator);guard service != 0 else {break};count+=1;defer {IOObjectRelease(service)}
                func field(_ key:String)->Any? {IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue()}
                if let connected=field("IsConnected") as? NSNumber,!connected.boolValue {continue}
                let transport=field("Transport") as? String ?? ""
                guard serviceClass=="AppleDeviceManagementHIDEventService" || transport.localizedCaseInsensitiveContains("Bluetooth") || transport.localizedCaseInsensitiveContains("USB") else {continue}
                let levels=["BatteryPercent","BatteryPercentLeft","BatteryPercentRight"].compactMap {(field($0) as? NSNumber)?.intValue}.filter {(0...100).contains($0)}
                guard let battery=levels.min() else {continue}
                let name=field("Product") as? String ?? field("ProductName") as? String ?? "Connected device"
                let key=String(name.prefix(100));values[key]=min(values[key] ?? battery,battery)
            }
        }
        return values.sorted {$0.key<$1.key}.map {($0.key,$0.value)}
    }
}

enum MacActivity {
    static var isActive:Bool {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0,
              let session=CGSessionCopyCurrentDictionary() as? [String:Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              let frontmost=NSWorkspace.shared.frontmostApplication,frontmost.bundleIdentifier != "com.apple.loginwindow" else {return false}
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!) < 180
    }
}

@MainActor final class PreferenceAlerts:ObservableObject {
    @Published var authorization="Not checked"
    @Published var permissionDenied=false
    @Published var accessoryState="Waiting for a supported connected accessory"
    private let defaults:UserDefaults
    private let sender:((String,String)->Void)?
    private var pressureSince:[String:Date]=[:]
    private var pressureAlerted=Set<String>()
    private var pressureRecovered:[String:Date]=[:]
    private var lastSample:Date?
    private var accessoryLow=Set<String>()
    private var dailyInFlight:String?
    private var diskLowSince:Date?
    init(defaults:UserDefaults = .standard,sender:((String,String)->Void)?=nil) {
        self.defaults=defaults;self.sender=sender
        defaults.register(defaults:["notificationsEnabled":true,"lowDiskAlerts":true,"resourceAlerts":true,"dailyUpdateAlerts":true,"leftoverAlerts":true,"bluetoothAlerts":true])
    }
    private var notificationsEnabled:Bool {defaults.bool(forKey:"notificationsEnabled")}
    func setNotificationsEnabled(_ enabled:Bool) {
        defaults.set(enabled,forKey:"notificationsEnabled")
        pressureSince=[:];pressureRecovered=[:];diskLowSince=nil
        if !enabled && sender==nil {UNUserNotificationCenter.current().removeAllPendingNotificationRequests()}
    }
    func request() async->Bool {
        do {let accepted=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]);await refreshAuthorization();return accepted}
        catch {authorization=error.localizedDescription;return false}
    }
    func refreshAuthorization() async {
        let status=await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permissionDenied = status == .denied
        switch status {case .authorized,.provisional,.ephemeral:authorization="Allowed";case .denied:authorization="Disabled in macOS Notifications";case .notDetermined:authorization="Permission not requested";@unknown default:authorization="Unavailable"}
    }
    func removeObsoleteNotifications() async {
        let obsolete:Set<String>=["Privacy activity","Keep Screen On enabled","Keep Screen On ended","Storage running low"]
        let center=UNUserNotificationCenter.current()
        let delivered=await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers:delivered.filter {obsolete.contains($0.request.content.title)}.map { $0.request.identifier })
        let pending=await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:pending.filter {obsolete.contains($0.content.title)}.map(\.identifier))
    }
    private func send(_ title:String,_ body:String,identifier:String=UUID().uuidString,completion:((Bool)->Void)?=nil) {
        guard notificationsEnabled else {completion?(false);return}
        if let sender {sender(title,body);completion?(true);return}
        Task {
            let center=UNUserNotificationCenter.current(),settings=await center.notificationSettings()
            guard notificationsEnabled,settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {completion?(false);return}
            let content=UNMutableNotificationContent();content.title=title;content.body=body
            do {try await center.add(UNNotificationRequest(identifier:identifier,content:content,trigger:nil));completion?(true)} catch {completion?(false)}
        }
    }
    func observe(_ sample:TelemetrySnapshot,accessories:[(String,Int)]?,now:Date=Date(),userActive:Bool=true) {
        if !userActive || lastSample.map({now.timeIntervalSince($0)>15 || now<$0}) == true {pressureSince=[:];pressureRecovered=[:];diskLowSince=nil}
        lastSample=now
        if userActive && notificationsEnabled && defaults.bool(forKey:"resourceAlerts") {
            let readings:[(String,Bool,Bool,TimeInterval,String)]=[
                ("CPU",sample.cpu.map {$0>=95} ?? false,sample.cpu.map {$0<80} ?? false,60,Self.pressureText("CPU",percent:sample.cpu)),
                ("GPU",sample.gpu.utilization.map {$0>=95} ?? false,sample.gpu.utilization.map {$0<80} ?? false,60,Self.pressureText("GPU",percent:sample.gpu.utilization)),
                ("RAM",sample.pressure=="Critical",sample.pressure=="Normal",30,Self.pressureText("RAM",percent:sample.memoryTotal>0 ? Double(sample.memoryUsed)/Double(sample.memoryTotal)*100:nil)),
                ("Thermal",["Serious","Critical"].contains(sample.thermal),["Nominal","Fair"].contains(sample.thermal),60,Self.thermalText(sample.thermal))]
            var messages:[String]=[]
            for (key,high,recovered,duration,message) in readings {
                if high {
                    pressureRecovered[key]=nil
                    if pressureSince[key]==nil {pressureSince[key]=now}
                    if now.timeIntervalSince(pressureSince[key]!)>=duration && !pressureAlerted.contains(key) {
                        let previous=defaults.object(forKey:"pressureAlert."+key) as? Date
                        if previous.map({now.timeIntervalSince($0)>=1800}) ?? true {
                            messages.append(message);pressureAlerted.insert(key);defaults.set(now,forKey:"pressureAlert."+key)
                        }
                    }
                } else {
                    pressureSince[key]=nil
                    if recovered {
                        if pressureRecovered[key]==nil {pressureRecovered[key]=now}
                        if now.timeIntervalSince(pressureRecovered[key]!)>=30 {pressureAlerted.remove(key)}
                    } else {pressureRecovered[key]=nil}
                }
            }
            if !messages.isEmpty {send(messages.joined(separator:"\n"),"",identifier:"bonsai.resource-pressure")}
        } else {pressureSince=[:];pressureRecovered=[:]}
        observeDisk(sample,now:now,userActive:userActive)
        if let accessories {
            accessoryState=accessories.isEmpty ? "No supported connected-device battery readings":accessories.map {"\($0.0): \($0.1)%"}.joined(separator:" · ")
            for (name,battery) in accessories where (0...100).contains(battery) {
                if battery>25 {accessoryLow.remove(name);defaults.removeObject(forKey:"batteryAlert."+name)}
                guard battery<=20,!accessoryLow.contains(name),notificationsEnabled,defaults.bool(forKey:"bluetoothAlerts") else {continue}
                accessoryLow.insert(name)
                let previous=defaults.object(forKey:"batteryAlert."+name) as? Date
                if previous.map({now.timeIntervalSince($0)>=21600}) ?? true {
                    defaults.set(now,forKey:"batteryAlert."+name)
                    send("Device battery low","\(name) is at \(battery)% battery.",identifier:"bonsai.battery."+name)
                }
            }
        }
    }
    private func observeDisk(_ sample:TelemetrySnapshot,now:Date,userActive:Bool) {
        guard notificationsEnabled,defaults.bool(forKey:"lowDiskAlerts"),userActive,
              sample.diskTotal>0,sample.diskFree<=sample.diskTotal else {diskLowSince=nil;return}
        // A small volume warns below 10%; a large volume warns below 20 GB.
        let threshold=min(sample.diskTotal/10,20*1024*1024*1024)
        guard sample.diskFree<=threshold else {diskLowSince=nil;return}
        if diskLowSince==nil {diskLowSince=now}
        guard now.timeIntervalSince(diskLowSince!)>=60 else {return}
        let previous=defaults.object(forKey:"lowDiskAlertDate") as? Date
        guard previous.map({now.timeIntervalSince($0)>=86400}) ?? true else {return}
        send("Low Disk Space : "+ByteCountFormatter.string(fromByteCount:Int64(clamping:sample.diskFree),countStyle:.file)+" available","",identifier:"bonsai.low-disk") {[weak self] accepted in
            if accepted {self?.defaults.set(now,forKey:"lowDiskAlertDate")}
        }
    }
    func observeTrash(_ notices:[TrashAppNotice]) {
        let paths=Set(notices.map { $0.url.path })
        let previous=defaults.stringArray(forKey:"knownTrashAppPaths").map(Set.init)
        defaults.set(Array(paths).sorted(),forKey:"knownTrashAppPaths")
        guard let previous,notificationsEnabled,defaults.bool(forKey:"leftoverAlerts") else {return}
        let new=notices.filter {!previous.contains($0.url.path)}
        guard !new.isEmpty else {return}
        let subject=new.count==1 ? new[0].name : "\(new.count) apps"
        send(Self.leftoversText(subject),"",identifier:"bonsai.app-leftovers")
    }
    func uninstalledApps(_ apps:[(name:String,recovery:String?)]) {
        guard !apps.isEmpty else {return}
        // Record exact recovery destinations so the background watcher cannot
        // repeat the notification for an uninstall Bonsai already reported.
        if let existing=defaults.stringArray(forKey:"knownTrashAppPaths") {
            defaults.set(Array(Set(existing).union(apps.compactMap(\.recovery))).sorted(),forKey:"knownTrashAppPaths")
        }
        guard notificationsEnabled,defaults.bool(forKey:"leftoverAlerts") else {return}
        let subject=apps.count==1 ? apps[0].name : "\(apps.count) apps"
        send(Self.leftoversText(subject),"",identifier:"bonsai.app-leftovers")
    }
    static func pressureText(_ resource:String,percent:Double?)->String {
        guard let percent,percent.isFinite,(0...100).contains(percent) else {return "High \(resource) Pressure"}
        return "High \(resource) Pressure : \(Int(percent.rounded()))%"
    }
    static func thermalText(_ status:String)->String {"High Thermal Pressure : \(status)"}
    static func leftoversText(_ subject:String)->String {subject+" removed to Trash. Review leftovers."}
    static func updateSummary(_ count:Int)->String {"\(count) app updates available"}
    private func day(_ date:Date)->String {String(Calendar.current.startOfDay(for:date).timeIntervalSince1970)}
    func needsDailyUpdates(now:Date=Date())->Bool {
        notificationsEnabled && defaults.bool(forKey:"dailyUpdateAlerts") && defaults.string(forKey:"dailyUpdateNotifiedDay") != day(now) && dailyInFlight != day(now)
    }
    func dailyUpdates(count:Int,checkedAt:Date,now:Date=Date(),userActive:Bool) {
        guard userActive,Calendar.current.isDate(checkedAt,inSameDayAs:now),needsDailyUpdates(now:now) else {return}
        let today=day(now);dailyInFlight=today
        send(Self.updateSummary(count),"",identifier:"bonsai.daily-updates") {[weak self] accepted in
            self?.dailyInFlight=nil
            if accepted {self?.defaults.set(today,forKey:"dailyUpdateNotifiedDay")}
        }
    }
    func previewNotifications() async {
        let center=UNUserNotificationCenter.current()
        let status=await center.notificationSettings().authorizationStatus
        var receipt:[String:Any]=["scheduled":[],"delivered":[]]
        func saveReceipt() {
            if let data=try? JSONSerialization.data(withJSONObject:receipt,options:.prettyPrinted) {
                try? data.write(to:URL(fileURLWithPath:"/tmp/bonsai-notification-preview-result.json"),options:.atomic)
            }
        }
        guard notificationsEnabled,status == .authorized || status == .provisional else {
            receipt["error"]="macOS notifications are not authorized for Bonsai.";saveReceipt();return
        }
        let examples:[(String,String)]=[
            (Self.pressureText("CPU",percent:96),""),
            (Self.pressureText("GPU",percent:90),""),
            (Self.pressureText("RAM",percent:94),""),
            (Self.thermalText("Critical"),""),
            ("Device battery low","Example Mouse is at 20% battery."),
            (Self.updateSummary(5),""),
            (Self.leftoversText("Example app"),"")]
        var identifiers:[String]=[]
        for (index,example) in examples.enumerated() {
            let content=UNMutableNotificationContent();content.title=example.0;content.body=example.1;content.subtitle="Preview"
            let id="bonsai.preview."+UUID().uuidString;identifiers.append(id)
            do {try await center.add(UNNotificationRequest(identifier:id,content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:Double(8+index*4),repeats:false)))}
            catch {receipt["error"]=error.localizedDescription}
        }
        receipt["scheduled"]=identifiers;saveReceipt()
        do {try await Task.sleep(for:.seconds(35))} catch {return}
        let delivered=await center.deliveredNotifications()
        receipt["delivered"]=delivered.map {$0.request.identifier}.filter {identifiers.contains($0)}
        let pending=await center.pendingNotificationRequests()
        receipt["pending"]=pending.map(\.identifier).filter {identifiers.contains($0)}
        saveReceipt()
    }

}
