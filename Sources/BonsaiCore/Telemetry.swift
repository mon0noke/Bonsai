import Foundation
import CBonsai
import IOKit
import IOKit.ps
import Darwin

public struct CounterSample: Sendable {
    public let time: TimeInterval; public let counters: [String:(UInt64,UInt64)]
    public init(time: TimeInterval,counters: [String:(UInt64,UInt64)]) { self.time=time; self.counters=counters }
}
public struct NetworkRate: Sendable { public let interface: String; public let download: Double; public let upload: Double }
public enum RateCalculator {
    public static func rates(previous: CounterSample?, current: CounterSample) -> [NetworkRate] {
        guard let previous,current.time > previous.time,current.time-previous.time < 30 else { return [] }
        return current.counters.sorted { $0.key < $1.key }.compactMap { name,value in
            guard let old=previous.counters[name],value.0>=old.0,value.1>=old.1 else { return nil }
            let elapsed=current.time-previous.time
            return NetworkRate(interface:name,download:Double(value.0-old.0)/elapsed,upload:Double(value.1-old.1)/elapsed)
        }
    }
}
public struct ProcessSample: Identifiable, Sendable {
    public var id: String { "\(pid):\(start):\(startMicro)" }
    public let pid: Int32; public let uid: UInt32; public let start: UInt64; public let startMicro: UInt64
    public let name: String; public let memory: UInt64; public let cpu: Double; public let cpuNS: UInt64
    public var powerScore:Double?;public var powerWatts:Double?;public var networkDownload:Double?;public var networkUpload:Double?
    public let parentPID:Int32; public let executable:String; public let metricsAvailable:Bool; public let cpuAvailable:Bool
    public init(pid:Int32,uid:UInt32,start:UInt64,startMicro:UInt64,name:String,memory:UInt64,cpu:Double,cpuNS:UInt64,parentPID:Int32=0,executable:String="",metricsAvailable:Bool=true,cpuAvailable:Bool=true,powerScore:Double?=nil,powerWatts:Double?=nil,networkDownload:Double?=nil,networkUpload:Double?=nil) {
        self.powerScore=powerScore;self.powerWatts=powerWatts;self.networkDownload=networkDownload;self.networkUpload=networkUpload
        self.pid=pid;self.uid=uid;self.start=start;self.startMicro=startMicro;self.name=name;self.memory=memory;self.cpu=cpu;self.cpuNS=cpuNS;self.parentPID=parentPID;self.executable=executable;self.metricsAvailable=metricsAvailable;self.cpuAvailable=cpuAvailable
    }
}
public struct TelemetrySnapshot: Sendable {
    public var temperaturePeak:Double?
    public var temperatures=TemperatureReading();public var batteryDetails=BatteryReading()
    public var swapUsed:UInt64=0
    public var networkNames:[String:String]=[:];public var primaryInterface:String?
    public var gpu=GPUSample(utilization:nil,cores:nil,model:"Apple GPU",state:"Awaiting first sample")
    public var date = Date(); public var cpu: Double?; public var loadAverages:[Double]=[]; public var memoryTotal: UInt64 = 0; public var memoryUsed: UInt64 = 0
    public var pressure = "Unavailable"; public var diskFree: UInt64 = 0; public var diskTotal: UInt64 = 0
    public var battery: Double?; public var batteryHealth = "Unavailable"; public var batteryCycles: Int?
    public var powerSource = "Unknown"; public var thermal = "Unknown"; public var uptime: TimeInterval = 0
    public var networks: [NetworkRate] = []; public var processes: [ProcessSample] = []; public var processGroups:[ProcessGroup]=[]; public var issues: [String] = []
    public init() {}
    public var health: String {
        if memoryTotal==0 || diskTotal==0 || pressure=="Unavailable" || thermal=="Unknown" { return "Metrics incomplete" }
        if pressure == "Critical" || pressure == "Warning" { return "Memory under pressure" }
        if diskTotal > 0 && Double(diskFree)/Double(diskTotal) < 0.1 { return "Storage running low" }
        if thermal == "Serious" || thermal == "Critical" { return "Thermal pressure" }
        return "No pressure detected"
    }
}
public actor TelemetryCollector {
    private var previousCPU: (UInt64,UInt64)?; private var previousNetwork: CounterSample?
    private var previousProcesses: [String:(UInt64,TimeInterval)] = [:]
    private var previousImpact:[String:(UInt64,UInt64,TimeInterval)]=[:]
    private var previousEnergy:[String:(UInt64,TimeInterval)]=[:]
    private let processNetwork=ProcessNetworkSampler()
    private let restrictedProcesses=RestrictedProcessSampler()
    private var temperatureHistory:[(TimeInterval,Double)]=[]
    private var sensorDate:TimeInterval=0;private var temperatures=TemperatureReading()
    private var networkLabelDate:TimeInterval=0;private var networkLabels:(names:[String:String],primary:String?)=([:],nil)
    public init() {}
    public func sample(applications:[ProcessApplication]=[],includeProcessNetwork:Bool=false,includeSystemMetrics:Bool=false) async -> TelemetrySnapshot {
        var value=TelemetrySnapshot();value.gpu=GPUTelemetry.sample(); let s=bonsai_system(); let time=ProcessInfo.processInfo.systemUptime
        if time-sensorDate>=4 {temperatures=TemperatureReading.read();sensorDate=time}
        value.temperatures=temperatures
        if let hottest=[temperatures.cpu,temperatures.gpu].compactMap({$0}).max() {temperatureHistory.append((time,hottest))}
        temperatureHistory.removeAll {time-$0.0>300};value.temperaturePeak=temperatureHistory.map(\.1).max()
        if time-networkLabelDate>=30 {networkLabels=NetworkConnectionLabels.read();networkLabelDate=time}
        value.networkNames=networkLabels.names;value.primaryInterface=networkLabels.primary
        var swap=xsw_usage();var swapSize=MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage",&swap,&swapSize,nil,0)==0 {value.swapUsed=swap.xsu_used}
        let total=s.user+s.system+s.idle+s.nice; let active=s.user+s.system+s.nice
        if s.valid != 0,let (oldTotal,oldActive)=previousCPU,total>oldTotal,active>=oldActive { value.cpu=min(100,Double(active-oldActive)/Double(total-oldTotal)*100) }
        previousCPU=(total,active); value.memoryTotal=s.total_memory; value.memoryUsed=min(s.total_memory,s.active_memory+s.wired_memory+s.compressed_memory)
        var loads=[Double](repeating:0,count:3)
        let loadCount=getloadavg(&loads,3)
        if loadCount>0 {value.loadAverages=Array(loads.prefix(Int(loadCount))).filter {$0.isFinite && $0>=0}}
        value.pressure = s.pressure == 1 ? "Normal" : s.pressure == 2 ? "Warning" : s.pressure == 4 ? "Critical" : "Unavailable"
        if let attr=try? FileManager.default.attributesOfFileSystem(forPath:FileManager.default.homeDirectoryForCurrentUser.path) { value.diskFree=(attr[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0; value.diskTotal=(attr[.systemSize] as? NSNumber)?.uint64Value ?? 0 }
        value.uptime=time
        switch ProcessInfo.processInfo.thermalState { case .nominal: value.thermal="Nominal"; case .fair: value.thermal="Fair"; case .serious: value.thermal="Serious"; case .critical: value.thermal="Critical"; @unknown default: value.thermal="Unknown" }
        var batteryFallback:[String:Any]=[:]
        if let blob=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let list=IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let d=IOPSGetPowerSourceDescription(blob,source)?.takeUnretainedValue() as? [String:Any],let current=d[kIOPSCurrentCapacityKey] as? Double,let max=d[kIOPSMaxCapacityKey] as? Double,max>0 {
                    batteryFallback=d
                    value.battery=min(100,current/max*100); value.powerSource=d[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
                    value.batteryHealth=d["BatteryHealth"] as? String ?? "Not reported by power-source API"
                }
            }
        }
        value.batteryDetails=BatteryReading.parse([:],fallback:batteryFallback)
        let service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var batteryProperties:[String:Any]=[:]
            for key in ["IsCharging","FullyCharged","ExternalConnected","Amperage","InstantAmperage","Voltage","AvgTimeToFull","AvgTimeToEmpty","TimeRemaining"] {
                if let field=IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() {batteryProperties[key]=field}
            }
            value.batteryDetails=BatteryReading.parse(batteryProperties,fallback:batteryFallback)
            if let n=IORegistryEntryCreateCFProperty(service,"CycleCount" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber { value.batteryCycles=n.intValue }
            if let max=IORegistryEntryCreateCFProperty(service,"AppleRawMaxCapacity" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber,let design=IORegistryEntryCreateCFProperty(service,"DesignCapacity" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber,design.doubleValue>0 { value.batteryHealth=String(format:"%.0f%% design capacity (registry estimate)",max.doubleValue/design.doubleValue*100) }
            if value.batteryHealth == "Not reported by power-source API", let data=IORegistryEntryCreateCFProperty(service,"BatteryData" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any],let full=data["FullChargeCapacity"] as? NSNumber,let design=data["DesignCapacity"] as? NSNumber,design.doubleValue>0,full.doubleValue>0 {
                value.batteryHealth=String(format:"%.0f%% design capacity (registry estimate)",full.doubleValue/design.doubleValue*100)
            }
            IOObjectRelease(service)
        }
        var interfaces=[bonsai_interface](repeating:bonsai_interface(),count:64)
        let n=bonsai_interfaces(&interfaces,64); var counters: [String:(UInt64,UInt64)] = [:]
        if n>=0 { for item in interfaces.prefix(Int(n)) { var name=item.name; let text=withUnsafePointer(to:&name) { $0.withMemoryRebound(to:CChar.self,capacity:64) { String(cString:$0) } }; counters[text]=(item.received,item.sent) } } else { value.issues.append("Interface counters unavailable") }
        let network=CounterSample(time:time,counters:counters); value.networks=RateCalculator.rates(previous:previousNetwork,current:network); previousNetwork=network
        var processes=[bonsai_process](repeating:bonsai_process(),count:4096); let count=bonsai_processes(&processes,4096); var next: [String:(UInt64,TimeInterval)] = [:]
        var nextEnergy:[String:(UInt64,TimeInterval)]=[:]
        var nextImpact:[String:(UInt64,UInt64,TimeInterval)]=[:]
        if count>=0 { for item in processes.prefix(Int(count)) {
            var name=item.name; let text=withUnsafePointer(to:&name) { $0.withMemoryRebound(to:CChar.self,capacity:256) { String(cString:$0) } }
            var path=item.executable;let executable=withUnsafePointer(to:&path) {$0.withMemoryRebound(to:CChar.self,capacity:1024) {String(cString:$0)}}
            let id="\(item.pid):\(item.start_sec):\(item.start_usec)"; var cpu=0.0;var cpuAvailable=false
            if item.metrics_valid != 0,let (old,when)=previousProcesses[id],item.cpu_ns>=old,time>when,time-when<30 { cpu=Double(item.cpu_ns-old)/(time-when)/1_000_000_000*100;cpuAvailable=true }
            if item.metrics_valid != 0 {next[id]=(item.cpu_ns,time)}
            var score:Double?
            if item.metrics_valid != 0 && item.wakeups_valid != 0 {
                if let old=previousImpact[id] {score=ProcessMetricRates.energyImpact(previousCPU:old.0,currentCPU:item.cpu_ns,previousWakeups:old.1,currentWakeups:item.idle_wakeups,elapsed:time-old.2)}
                nextImpact[id]=(item.cpu_ns,item.idle_wakeups,time)
            }
            var watts:Double?
            if item.energy_valid != 0 {
                if let old=previousEnergy[id] {watts=ProcessMetricRates.watts(previous:old.0,current:item.energy_nj,elapsed:time-old.1)}
                nextEnergy[id]=(item.energy_nj,time)
            }
            value.processes.append(ProcessSample(pid:item.pid,uid:item.uid,start:item.start_sec,startMicro:item.start_usec,name:text,memory:item.resident,cpu:cpu,cpuNS:item.cpu_ns,parentPID:item.parent_pid,executable:executable,metricsAvailable:item.metrics_valid != 0,cpuAvailable:cpuAvailable,powerScore:score,powerWatts:watts))
        } } else { value.issues.append("Process information unavailable") }
        previousImpact=nextImpact
        previousEnergy=nextEnergy
        let traffic=await processNetwork.sample(processes:value.processes,enabled:includeProcessNetwork)
        for i in value.processes.indices {if let rate=traffic[value.processes[i].id] {value.processes[i].networkDownload=rate.download;value.processes[i].networkUpload=rate.upload}}
        let restricted=await restrictedProcesses.sample(processes:value.processes,enabled:includeSystemMetrics)
        for i in value.processes.indices {if let reading=restricted[value.processes[i].id] {value.processes[i]=value.processes[i].applyingRestricted(reading)}}
        previousProcesses=next; value.processes.sort { $0.cpu > $1.cpu }
        value.processGroups=ProcessGrouping.groups(value.processes,applications:applications)
        if count==4096 {value.issues.append("Process capacity reached; the list may be incomplete.")}
        return value
    }
    public static func terminate(_ selected: ProcessSample,force:Bool=false) throws {
        guard selected.uid==getuid(),selected.pid>1,selected.pid != getpid() else { throw BonsaiError.refused("Only your own processes can be terminated. Bonsai and system processes are protected.") }
        var current=bonsai_process(); guard bonsai_process_identity(selected.pid,&current) != 0,current.uid==selected.uid,current.start_sec==selected.start,current.start_usec==selected.startMicro else { throw BonsaiError.changed("Process identity changed or exited. Refresh and review again.") }
        guard kill(selected.pid,force ? SIGKILL : SIGTERM)==0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
    }
}
