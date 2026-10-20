import Foundation
import IOKit
import SystemConfiguration
import CBonsai

public struct TemperatureReading:Sendable {
    public var cpu:Double?;public var gpu:Double?
    public init(cpu:Double?=nil,gpu:Double?=nil) {self.cpu=cpu;self.gpu=gpu}
    public static func read()->TemperatureReading {
        var cpu=Double.nan,gpu=Double.nan
        _=bonsai_temperatures(&cpu,&gpu)
        return .init(cpu:cpu.isFinite ? cpu:nil,gpu:gpu.isFinite ? gpu:nil)
    }
}
public struct BatteryReading:Sendable {
    public var charging:Bool?;public var full=false;public var externalPower:Bool?
    public var watts:Double?;public var minutesToFull:Int?;public var minutesRemaining:Int?
    public init() {}
    public static func parse(_ properties:[String:Any],fallback:[String:Any]=[:])->BatteryReading {
        var result=BatteryReading()
        func bool(_ key:String,_ alternate:String)->Bool? {(properties[key] as? NSNumber)?.boolValue ?? (fallback[alternate] as? NSNumber)?.boolValue}
        func minutes(_ keys:[String],fallbackKey:String)->Int? {
            let values=keys.compactMap {(properties[$0] as? NSNumber)?.intValue}+[(fallback[fallbackKey] as? NSNumber)?.intValue].compactMap {$0}
            return values.first {(1...1440).contains($0)}
        }
        result.charging=bool("IsCharging","Is Charging");result.full=bool("FullyCharged","Is Charged") ?? false
        result.externalPower=(properties["ExternalConnected"] as? NSNumber)?.boolValue ?? (fallback["Power Source State"] as? String).map {$0=="AC Power"}
        let current=(properties["Amperage"] as? NSNumber) ?? (properties["InstantAmperage"] as? NSNumber) ?? (fallback["Current"] as? NSNumber)
        let voltage=(properties["Voltage"] as? NSNumber) ?? (fallback["Voltage"] as? NSNumber)
        if let current,let voltage,abs(Double(current.int64Value))<=20000,(5000...30000).contains(voltage.doubleValue) {
            result.watts=abs(Double(current.int64Value))*voltage.doubleValue/1_000_000
        }
        if result.charging==true && !result.full {result.minutesToFull=minutes(["AvgTimeToFull","TimeRemaining"],fallbackKey:"Time to Full Charge")}
        if result.charging==false && result.externalPower != true {result.minutesRemaining=minutes(["AvgTimeToEmpty","TimeRemaining"],fallbackKey:"Time to Empty")}
        return result
    }
}
public enum StatusMetricLabels {
    public static func memoryPressure(_ state:String,utilization:Double)->String {
        switch state {case "Critical":return "Very High";case "Warning":return "High";case "Normal":return utilization>=75 ? "Medium":"Light";default:return "—"}
    }
    public static func cpuSeverity(_ utilization:Double)->Int {utilization>=80 ? 2:utilization>=40 ? 1:0}
}
public enum NetworkConnectionLabels {
    public static func read()->(names:[String:String],primary:String?) {
        var names:[String:String]=[:]
        if let interfaces=SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                guard let name=SCNetworkInterfaceGetBSDName(interface) as String?,let type=SCNetworkInterfaceGetInterfaceType(interface) else {continue}
                if CFEqual(type,kSCNetworkInterfaceTypeIEEE80211) {names[name]="Wi-Fi"}
                else if CFEqual(type,kSCNetworkInterfaceTypeEthernet) {names[name]="Ethernet"}
                else if CFEqual(type,kSCNetworkInterfaceTypeWWAN) {names[name]="Cellular"}
                else {names[name]=SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "Network"}
            }
        }
        let state=SCDynamicStoreCopyValue(nil,"State:/Network/Global/IPv4" as CFString) as? [String:Any]
        return (names,state?["PrimaryInterface"] as? String)
    }
    public static func fallback(_ interface:String)->String {
        if interface.hasPrefix("utun") || interface.hasPrefix("ppp") {return "VPN"}
        if interface.hasPrefix("bridge") {return "Bridge"}
        return "Network"
    }
}
