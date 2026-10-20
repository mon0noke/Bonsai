import Foundation
import BonsaiCore
import CBonsai
import Darwin

@main struct EnergyImpactVerify {
 static func main() async throws {
  var count=0
  func check(_ value:Bool,_ label:String) {precondition(value,label);count+=1}
  check(ProcessMetricRates.energyImpact(previousCPU:0,currentCPU:1_000_000_000,previousWakeups:0,currentWakeups:100,elapsed:2)==52.5,"CPU time and wakeups produce the published relative weighting")
  check(ProcessMetricRates.energyImpact(previousCPU:10,currentCPU:10,previousWakeups:4,currentWakeups:4,elapsed:2)==0,"Idle process score is zero")
  check(ProcessMetricRates.energyImpact(previousCPU:10,currentCPU:9,previousWakeups:0,currentWakeups:0,elapsed:2)==nil,"CPU reset rejected")
  check(ProcessMetricRates.energyImpact(previousCPU:0,currentCPU:10,previousWakeups:4,currentWakeups:3,elapsed:2)==nil,"Wakeup reset rejected")
  check(ProcessMetricRates.energyImpact(previousCPU:0,currentCPU:10,previousWakeups:0,currentWakeups:0,elapsed:30)==nil,"No stale score after sleep")
  check(ProcessMetricRates.energyImpact(previousCPU:0,currentCPU:2_000_000_000,previousWakeups:0,currentWakeups:0,elapsed:1)==200,"Multicore scores are not incorrectly capped at 100")
  var base=mach_timebase_info_data_t();mach_timebase_info(&base)
  check(bonsai_cpu_nanoseconds(24000)==24000*UInt64(base.numer)/UInt64(base.denom),"Mach CPU ticks converted into real nanoseconds")
  func p(_ pid:Int32,_ app:String,_ score:Double?)->ProcessSample {ProcessSample(pid:pid,uid:501,start:1,startMicro:0,name:app,memory:1,cpu:1,cpuNS:1,executable:"/Applications/"+app+".app/Contents/MacOS/"+app,powerScore:score)}
  let groups=ProcessGrouping.groups([p(1,"A",2),p(2,"A",3),p(3,"B",nil),p(4,"C",1)])
  let a=groups.first {$0.name=="A"}!
  check(a.powerScore==5 && a.powerScoreComplete,"App impact includes helpers")
  for ascending in [true,false] {check(ProcessGrouping.presented(groups,query:"",sort:.power,ascending:ascending,pinned:[]).last?.name=="B","Unknown scores remain last")}
  check(ProcessGrouping.presented(groups,query:"",sort:.power,ascending:false,pinned:[]).first?.name=="A","Power sorts by impact score")
  let partial=ProcessGrouping.groups([p(1,"A",2),p(2,"A",nil)])[0]
  check(partial.powerScore==2 && !partial.powerScoreComplete,"Incomplete impact totals stay marked partial")
  let collector=TelemetryCollector();_=await collector.sample();try await Task.sleep(for:.milliseconds(150));let live=await collector.sample()
  check(live.processGroups.contains {$0.powerScore != nil},"Live score samples available")
  print("PASS \(count) energy impact checks")
 }
}
