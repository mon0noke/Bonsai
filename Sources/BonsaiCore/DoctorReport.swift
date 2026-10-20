import Foundation
import Darwin

public struct DoctorRow:Identifiable,Sendable {
    public var id:String {label};public let label:String;public let value:String
    public init(_ label:String,_ value:String) {self.label=label;self.value=value}
}
public struct DoctorSection:Identifiable,Sendable {
    public var id:String {title};public let title:String;public let rows:[DoctorRow]
    public init(_ title:String,_ rows:[DoctorRow]) {self.title=title;self.rows=rows}
}
public struct DoctorReport:Sendable {
    public let date:Date;public let sampleDate:Date;public let issues:[String];public let sections:[DoctorSection]
    public var text:String {
        (["Bonsai Doctor · "+date.formatted(),"Telemetry sample · "+sampleDate.formatted(),"Detected issues",issues.isEmpty ? "No issue detected in this snapshot":issues.joined(separator:"\n")]+sections.flatMap {[$0.title]+$0.rows.map {$0.label+": "+$0.value}}).joined(separator:"\n")
    }
    public static func detected(_ snapshot:TelemetrySnapshot,now:Date=Date())->[String] {
        var result=snapshot.issues
        if now.timeIntervalSince(snapshot.date)>15 {result.append("Live sample is stale. Open Status to check collection.")}
        if ["Warning","Critical"].contains(snapshot.pressure) {result.append("Memory pressure is "+snapshot.pressure.lowercased()+". Review apps in Status.")}
        if snapshot.diskTotal>0,Double(snapshot.diskFree)/Double(snapshot.diskTotal)<0.1 {result.append("Less than 10% of startup disk capacity is free.")}
        if ["Serious","Critical"].contains(snapshot.thermal) {result.append("macOS reports elevated thermal pressure.")}
        if let cpu=snapshot.cpu,cpu>85 {result.append("High CPU in this sample; check sustained activity in Status.")}
        return result
    }
    public static func make(snapshot:TelemetrySnapshot,access:FileAccessReport,environment:[DoctorRow],configuration:[DoctorRow],runtime:[DoctorRow],now:Date=Date())->DoctorReport {
        func size(_ value:UInt64)->String {ByteCountFormatter.string(fromByteCount:Int64(clamping:value),countStyle:.file)}
        var loads=[Double](repeating:0,count:3);let loadCount=getloadavg(&loads,3)
        let system:[DoctorRow]=[
            DoctorRow("Health",snapshot.health),DoctorRow("CPU",snapshot.cpu.map {String(format:"%.1f%%",$0)} ?? "Awaiting baseline"),
            DoctorRow("Load average",loadCount==3 ? loads.map {String(format:"%.2f",$0)}.joined(separator:" / "):"Unavailable"),
            DoctorRow("Memory",size(snapshot.memoryUsed)+" / "+size(snapshot.memoryTotal)),DoctorRow("Memory pressure",snapshot.pressure),
            DoctorRow("Thermal pressure",snapshot.thermal),DoctorRow("GPU",snapshot.gpu.utilization.map {String(format:"%.1f%%",$0)+" · "+snapshot.gpu.state} ?? snapshot.gpu.state),DoctorRow("°C / fans","No supported source enabled"),
            DoctorRow("Startup disk",size(snapshot.diskFree)+" free / "+size(snapshot.diskTotal)),
            DoctorRow("Battery",snapshot.battery.map {String(format:"%.0f%%",$0)+" · "+snapshot.powerSource} ?? "Not reported"),
            DoctorRow("Battery health",snapshot.batteryHealth),DoctorRow("Battery cycles",snapshot.batteryCycles.map(String.init) ?? "Unavailable"),
            DoctorRow("Low Power Mode",ProcessInfo.processInfo.isLowPowerModeEnabled ? "On":"Off"),
            DoctorRow("Uptime","\(Int(snapshot.uptime/86400))d \(Int(snapshot.uptime/3600)%24)h \(Int(snapshot.uptime/60)%60)m"),
            DoctorRow("Health inputs","Memory pressure, <10% free disk, thermal pressure"),
            DoctorRow("Network",snapshot.networks.isEmpty ? "Awaiting counter baseline":snapshot.networks.prefix(8).map {$0.interface+" ↓"+size(UInt64(max(0,$0.download)))+"/s ↑"+size(UInt64(max(0,$0.upload)))+"/s"}.joined(separator:" · "))]
        let processes=snapshot.processes.sorted {$0.memory>$1.memory}.prefix(5).map {DoctorRow(String($0.name.unicodeScalars.filter {!CharacterSet.controlCharacters.contains($0)}.map(String.init).joined().prefix(120)),size($0.memory)+" · "+($0.cpuAvailable ? String(format:"%.1f%% CPU",$0.cpu):"CPU baseline"))}
        let permissions=access.probes.map {DoctorRow($0.title,$0.status == .readable ? "Readable":$0.status == .blocked ? "Access needed":$0.status == .missing ? "Not present":"Could not check")}
        return DoctorReport(date:now,sampleDate:snapshot.date,issues:detected(snapshot,now:now)+(access.needsAccess ? ["Protected folder access is missing. Manage Full Disk Access in Settings."]:[]),sections:[DoctorSection("Environment",environment),DoctorSection("System",system),DoctorSection("Top processes · by memory",processes),DoctorSection("Permissions · metadata probes",permissions),DoctorSection("Configuration",configuration),DoctorSection("Runtime",runtime)])
    }
    public static func hardware(_ key:String)->String {
        var count=0;guard sysctlbyname(key,nil,&count,nil,0)==0,count>0,count<=4096 else {return "Unavailable"}
        var data=[CChar](repeating:0,count:count);guard sysctlbyname(key,&data,&count,nil,0)==0 else {return "Unavailable"}
        return String(cString:data)
    }
}
