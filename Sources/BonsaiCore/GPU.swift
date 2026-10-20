import Foundation
import IOKit

public struct GPUSample:Sendable {
    public let utilization:Double?;public let cores:Int?;public let model:String;public let state:String
    public init(utilization:Double?,cores:Int?,model:String,state:String) {self.utilization=utilization;self.cores=cores;self.model=model;self.state=state}
}
public enum GPUTelemetry {
    public static func parse(_ statistics:[String:Any],cores:Any?=nil,model:String="Apple GPU")->GPUSample {
        var utilization:Double?
        // AGX driver snapshots are a conditional capability, not a stable Metal API.
        if let number=statistics["Device Utilization %"] as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.isFinite,(0...100).contains(number.doubleValue) {utilization=number.doubleValue}
        let count=(cores as? NSNumber)?.intValue
        return GPUSample(utilization:utilization,cores:count.flatMap {(1...256).contains($0) ? $0:nil},model:model,state:utilization==nil ? "Driver utilization not exposed":"AGX driver snapshot")
    }
    public static func sample()->GPUSample {
        let service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AGXAccelerator"))
        guard service != 0 else {return GPUSample(utilization:nil,cores:nil,model:"Apple GPU",state:"GPU driver unavailable")}
        defer {IOObjectRelease(service)}
        func property(_ key:String)->CFTypeRef? {IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue()}
        let statistics=property("PerformanceStatistics") as? [String:Any] ?? [:]
        return parse(statistics,cores:property("gpu-core-count"),model:property("model") as? String ?? "Apple GPU")
    }
}
