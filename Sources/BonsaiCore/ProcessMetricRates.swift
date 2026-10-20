import Foundation
import CBonsai
import Darwin

public enum ProcessMetricRates {
    /// Relative CPU-plus-idle-wakeup impact, using the weighting published in
    /// Apple's top power.c: CPU time plus 500 microseconds per idle wakeup.
    /// This is a comparison score, not watts, a percentage or a battery estimate.
    public static func energyImpact(previousCPU:UInt64,currentCPU:UInt64,previousWakeups:UInt64,currentWakeups:UInt64,elapsed:TimeInterval)->Double? {
        guard elapsed>0,elapsed<30,currentCPU>=previousCPU,currentWakeups>=previousWakeups else {return nil}
        return (Double(currentCPU-previousCPU)/1_000_000_000+Double(currentWakeups-previousWakeups)*0.0005)/elapsed*100
    }
    public static func watts(previous:UInt64,current:UInt64,elapsed:TimeInterval)->Double? {
        guard elapsed>0,elapsed<30,current>=previous else {return nil}
        return Double(current-previous)/1_000_000_000/elapsed
    }
    /// nettop's selected output has a process label followed by raw byte counters.
    /// Parse from the right so commas in a process name cannot shift the columns.
    public static func networkCounters(_ output:String)->[Int32:(UInt64,UInt64)]? {
        guard output.utf8.count<=2_097_152 else {return nil}
        var counters:[Int32:(UInt64,UInt64)]=[:];var header=false
        for line in output.split(separator:"\n") {
            var fields=line.split(separator:",",omittingEmptySubsequences:false).map(String.init)
            if fields.last=="" {fields.removeLast()}
            if fields.suffix(2)==["bytes_in","bytes_out"] {header=true;continue}
            guard fields.count>=3 else {continue}
            let label=fields.dropLast(2).joined(separator:",")
            guard let dot=label.lastIndex(of:"."),let pid=Int32(label[label.index(after:dot)...]),pid>0 else {continue}
            guard let received=UInt64(fields[fields.count-2]),let sent=UInt64(fields[fields.count-1]),counters[pid]==nil else {return nil}
            counters[pid]=(received,sent)
        }
        return header ? counters:nil
    }
}

actor ProcessNetworkSampler {
    private var lastAttempt:TimeInterval=0
    private var previous:[String:(UInt64,UInt64,TimeInterval)]=[:]
    private var rates:[String:NetworkRate]=[:]
    private var sampling=false
    func sample(processes:[ProcessSample],enabled:Bool) async -> [String:NetworkRate] {
        guard enabled else {previous=[:];rates=[:];lastAttempt=0;return [:]}
        let now=ProcessInfo.processInfo.systemUptime
        guard !sampling,now-lastAttempt>=6 else {return rates}
        sampling=true;lastAttempt=now
        defer {sampling=false}
        guard let result=try? await CommandRunner.processNetworkCounters(),result.succeeded,
              let counters=ProcessMetricRates.networkCounters(result.standardOutput) else {previous=[:];rates=[:];return [:]}
        let time=ProcessInfo.processInfo.systemUptime
        var next:[String:(UInt64,UInt64,TimeInterval)]=[:],fresh:[String:NetworkRate]=[:]
        for p in processes {
            // PID alone is insufficient: reject exited/reused identities after nettop.
            var current=bonsai_process()
            guard bonsai_process_identity(p.pid,&current) != 0,current.uid==p.uid,current.start_sec==p.start,current.start_usec==p.startMicro else {continue}
            guard counters[p.pid] != nil || p.uid==getuid() else {continue}
            let bytes=counters[p.pid] ?? (0,0)
            next[p.id]=(bytes.0,bytes.1,time)
            if let old=previous[p.id],time>old.2,time-old.2<30,bytes.0>=old.0,bytes.1>=old.1 {
                fresh[p.id]=NetworkRate(interface:"process",download:Double(bytes.0-old.0)/(time-old.2),upload:Double(bytes.1-old.1)/(time-old.2))
            }
        }
        previous=next;rates=fresh;return fresh
    }
}
