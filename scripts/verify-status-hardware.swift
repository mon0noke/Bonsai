import Foundation
import BonsaiCore
import CBonsai

@main struct StatusHardwareVerify {
    static func main() async throws {
        var count=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);count+=1}
        var fp:[UInt8]=[0,0,74,66] // native Float(50.5)
        check(bonsai_decode_temperature(0x666c7420,&fp,4)==50.5,"Float sensor decoding")
        var fixed:[UInt8]=[50,128]
        check(bonsai_decode_temperature(0x73703738,&fixed,2)==50.5,"Signed fixed point sensor decoding")
        check(bonsai_decode_temperature(0x666c7420,&fp,2).isNaN,"Wrong sensor length rejected")
        var zero:[UInt8]=[0,0,0,0]
        check(bonsai_decode_temperature(0x666c7420,&zero,4).isNaN,"Zero placeholder is unavailable")
        var nan:[UInt8]=[0,0,192,127]
        check(bonsai_decode_temperature(0x666c7420,&nan,4).isNaN,"Invalid sensor values rejected")
        check(StatusMetricLabels.memoryPressure("Normal",utilization:40)=="Light","Low normal pressure")
        check(StatusMetricLabels.memoryPressure("Normal",utilization:80)=="Medium","Elevated normal utilization")
        check(StatusMetricLabels.memoryPressure("Warning",utilization:50)=="High","Kernel warning remains high pressure")
        check(StatusMetricLabels.memoryPressure("Critical",utilization:50)=="Very High","Critical pressure")
        check(StatusMetricLabels.memoryPressure("Unavailable",utilization:0)=="—","No invented pressure")
        for (value,level) in [(0.0,0),(39.9,0),(40,1),(79.9,1),(80,2),(200,2)] {check(StatusMetricLabels.cpuSeverity(value)==level,"CPU color thresholds")}
        let charging=BatteryReading.parse(["IsCharging":true,"ExternalConnected":true,"Amperage":2000,"Voltage":12000,"AvgTimeToFull":40])
        check(charging.charging==true && charging.externalPower==true && charging.watts==24 && charging.minutesToFull==40,"Charging power and full-charge estimate")
        let draining=BatteryReading.parse(["IsCharging":false,"ExternalConnected":false,"Amperage":NSNumber(value:UInt64.max-999),"Voltage":12000,"AvgTimeToEmpty":120])
        check(draining.watts==12 && draining.minutesRemaining==120 && draining.minutesToFull==nil,"Unsigned registry representation of negative discharge current")
        let unknown=BatteryReading.parse(["IsCharging":true,"AvgTimeToFull":65535,"TimeRemaining":0,"Amperage":1000000000,"Voltage":12000])
        check(unknown.minutesToFull==nil && unknown.watts==nil,"Unknown estimates and invalid power remain unavailable")
        let full=BatteryReading.parse(["FullyCharged":true,"IsCharging":false,"ExternalConnected":true,"AvgTimeToFull":10])
        check(full.full && full.minutesToFull==nil && full.minutesRemaining==nil,"Full battery does not show discharge or a charging estimate")
        check(NetworkConnectionLabels.fallback("utun4")=="VPN","VPN connection naming")
        let collector=TelemetryCollector();let sample=await collector.sample()
        check(sample.networkNames.values.contains("Wi-Fi") || sample.networkNames.values.contains("Ethernet"),"Live network hardware mapping")
        if let cpu=sample.temperatures.cpu {check((5...125).contains(cpu),"Live CPU sensor bounds")}
        if let gpu=sample.temperatures.gpu {check((5...125).contains(gpu),"Live GPU sensor bounds")}
        print("PASS \(count) status hardware checks")
        print("Live CPU:",sample.temperatures.cpu as Any,"GPU:",sample.temperatures.gpu as Any,"Charging:",sample.batteryDetails.charging as Any,"Battery watts:",sample.batteryDetails.watts as Any,"Minutes to full:",sample.batteryDetails.minutesToFull as Any)
    }
}
