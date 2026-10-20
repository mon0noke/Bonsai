import Foundation
import CBonsai
import Darwin

public struct RestrictedProcessReading:Sendable {
    public let cpu:Double;public let powerScore:Double;public let resident:UInt64?
}
public enum SystemProcessOutput {
    /// Keep only the final interval: top's first sample has no CPU baseline.
    public static func usage(_ output:String)->[Int32:(cpu:Double,power:Double)]? {
        guard output.utf8.count<=2_097_152 else {return nil}
        var result:[Int32:(cpu:Double,power:Double)]=[:];var headers=0
        for line in output.split(separator:"\n") {
            let fields=line.split(whereSeparator:{$0==" " || $0=="\t"})
            if fields==["PID","%CPU","POWER"] {result=[:];headers+=1;continue}
            guard headers>0,fields.count==3,let pid=Int32(fields[0]),pid>1 else {continue}
            guard let cpu=Double(fields[1]),let power=Double(fields[2]),cpu.isFinite,power.isFinite,(0...100_000).contains(cpu),(0...1_000_000).contains(power),result[pid]==nil else {return nil}
            result[pid]=(cpu,power)
        }
        return headers>=2 ? result:nil
    }
    public static func residentMemory(_ output:String)->[Int32:UInt64]? {
        guard output.utf8.count<=524_288 else {return nil}
        var result:[Int32:UInt64]=[:]
        for line in output.split(separator:"\n") {
            let fields=line.split(whereSeparator:{$0==" " || $0=="\t"})
            guard fields.count==2,let pid=Int32(fields[0]),pid>1 else {continue}
            guard let kib=UInt64(fields[1]),kib<=UInt64.max/1024,result[pid]==nil else {return nil}
            result[pid]=kib*1024
        }
        return result
    }
}
extension ProcessSample {
    func applyingRestricted(_ reading:RestrictedProcessReading)->ProcessSample {
        ProcessSample(pid:pid,uid:uid,start:start,startMicro:startMicro,name:name,memory:reading.resident ?? memory,cpu:reading.cpu,cpuNS:cpuNS,parentPID:parentPID,executable:executable,metricsAvailable:reading.resident != nil || metricsAvailable,cpuAvailable:true,powerScore:reading.powerScore,powerWatts:powerWatts,networkDownload:networkDownload,networkUpload:networkUpload)
    }
}
actor RestrictedProcessSampler {
    private var lastAttempt:TimeInterval=0
    private var cached:[String:RestrictedProcessReading]=[:]
    private var sampling=false
    func sample(processes:[ProcessSample],enabled:Bool) async->[String:RestrictedProcessReading] {
        guard enabled else {lastAttempt=0;cached=[:];return [:]}
        let needed=processes.filter {$0.uid != getuid() && (!$0.metricsAvailable || $0.powerScore==nil)}
        guard !needed.isEmpty else {return [:]}
        let time=ProcessInfo.processInfo.systemUptime
        guard !sampling,time-lastAttempt>=6 else {return time-lastAttempt<15 ? cached:[:]}
        sampling=true;lastAttempt=time;defer {sampling=false}
        async let usage=CommandRunner.systemProcessUsage()
        async let memory=CommandRunner.systemResidentMemory()
        guard let stats=try? await usage,stats.succeeded,let measured=SystemProcessOutput.usage(stats.standardOutput) else {cached=[:];return [:]}
        let rssResult=try? await memory
        let rss=rssResult.flatMap {$0.succeeded ? SystemProcessOutput.residentMemory($0.standardOutput):nil} ?? [:]
        var next:[String:RestrictedProcessReading]=[:]
        for p in needed {
            var current=bonsai_process()
            guard let reading=measured[p.pid],bonsai_process_identity(p.pid,&current) != 0,current.uid==p.uid,current.start_sec==p.start,current.start_usec==p.startMicro else {continue}
            next[p.id]=RestrictedProcessReading(cpu:reading.cpu,powerScore:reading.power,resident:rss[p.pid])
        }
        cached=next;return next
    }
}
