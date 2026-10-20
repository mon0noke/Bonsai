import Foundation

/// A transparent pressure score, not a diagnosis or a hardware reliability rating.
public struct HealthAssessment:Sendable {
    public let score:Int?
    public let label:String
    public let explanation:String
    public var title:String {score.map {"\($0) \(label)"} ?? "— \(label)"}
    public static func evaluate(_ sample:TelemetrySnapshot,now:Date=Date())->HealthAssessment {
        guard now.timeIntervalSince(sample.date)<=10,now.timeIntervalSince(sample.date)>=(-2) else {return .init(score:nil,label:"Waiting",explanation:"The live sample is stale. Waiting for fresh readings.")}
        guard sample.memoryTotal>0,sample.diskTotal>0,sample.diskFree<=sample.diskTotal,["Normal","Warning","Critical"].contains(sample.pressure),["Nominal","Fair","Serious","Critical"].contains(sample.thermal) else {return .init(score:nil,label:"Waiting",explanation:"Memory pressure, disk capacity or thermal state is unavailable.")}
        let memory=sample.pressure=="Critical" ? 45 : sample.pressure=="Warning" ? 16 : 0
        let free=Double(sample.diskFree)/Double(sample.diskTotal)*100
        let storage=Int(min(30,max(0,(20-free)*1.5)).rounded())
        let thermal=sample.thermal=="Critical" ? 50 : sample.thermal=="Serious" ? 30 : sample.thermal=="Fair" ? 8 : 0
        let score=max(0,100-memory-storage-thermal)
        let reasons=[memory>0 ? "Memory pressure −\(memory)":nil,storage>0 ? "Low free storage −\(storage)":nil,thermal>0 ? "Thermal pressure −\(thermal)":nil].compactMap {$0}
        return .init(score:score,label:score>=70 ? "Good" : score>=40 ? "Fair":"Needs care",explanation:reasons.isEmpty ? "No pressure detected":reasons.joined(separator:" · "))
    }
    public static let inputs="Starts at 100. Memory pressure deducts 16 for Warning or 45 for Critical. Below 20% free storage, each percentage point deducts 1.5, capped at 30. Thermal state deducts 8 for Fair, 30 for Serious or 50 for Critical. Good: 70–100; Fair: 40–69; Needs care: 0–39. Missing or stale inputs show no score. CPU, GPU and battery charge do not affect this pressure score."
}
public enum TemperatureUnit:String,CaseIterable {case celsius="°C",fahrenheit="°F"
    public func format(celsius:Double?)->String {guard let celsius,celsius.isFinite else {return "Unavailable"};return String(format:"%.0f%@",self == .celsius ? celsius : celsius*9/5+32,rawValue)}
}
public enum CacheRemovalMode:String,CaseIterable {case trash="Trash",permanent="Permanent"}
public enum AwakeBehavior:String,CaseIterable {case screenAndWork="Screen and Work",workOnly="Work Only",screenOnly="Screen Only"}
