import Foundation

/// Measured bytes, never a prediction of reclaimable space or work percentage.
public struct CleanScanActivity:Sendable {
    public let location:String
    public let allocated:UInt64
    public init(location:String,allocated:UInt64) {self.location=location;self.allocated=allocated}
}

/// A single catalog scan is node-bounded; count shared inodes once across its paths.
final class CleanScanMeter:@unchecked Sendable {
    private let lock=NSLock()
    private var seen=Set<String>()
    private var allocated:UInt64=0
    private var lastEmission:Double=0
    private let emit:@Sendable(CleanScanActivity)->Void
    init(emit:@escaping @Sendable(CleanScanActivity)->Void) {self.emit=emit}
    func record(_ identity:Identity,bytes:UInt64,location:String) {
        lock.lock()
        if seen.insert("\(identity.device):\(identity.inode)").inserted {
            let sum=allocated.addingReportingOverflow(bytes);allocated=sum.overflow ? .max : sum.partialValue
        }
        let now=ProcessInfo.processInfo.systemUptime
        let publish=now-lastEmission>=0.1
        if publish {lastEmission=now}
        let value=CleanScanActivity(location:location,allocated:allocated)
        lock.unlock()
        if publish {emit(value)}
    }
    func publish(location:String) {
        lock.lock();let value=CleanScanActivity(location:location,allocated:allocated);lastEmission=ProcessInfo.processInfo.systemUptime;lock.unlock()
        emit(value)
    }
}
