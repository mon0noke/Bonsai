import Foundation
import BonsaiCore
import CBonsai
import Darwin

@main struct SystemProcessesVerify {
 static func main() async throws {
  var count=0
  func check(_ condition:Bool,_ message:String) {precondition(condition,message);count+=1}
  let output="Processes: 2\nPID %CPU POWER\n178 0.0 0.0\n432 0.0 0.0\nPID %CPU POWER\n178 32.1 34.6\n432 2.0 3.0\n"
  let readings=SystemProcessOutput.usage(output)
  check(readings?.count==2 && readings?[178]?.cpu==32.1 && readings?[178]?.power==34.6,"Use final interval rather than top's zero baseline")
  check(SystemProcessOutput.usage("PID %CPU POWER\n178 0 0")==nil,"Do not invent readings from an initial baseline")
  check(SystemProcessOutput.usage(output+"178 0 0\n")==nil,"Reject duplicate PID records")
  check(SystemProcessOutput.usage("PID %CPU POWER\nPID %CPU POWER\n178 nan 1")==nil,"Reject invalid CPU counters")
  let rss=SystemProcessOutput.residentMemory(" 178 146000\n 432 1024\n")
  check(rss?[178]==149504000 && rss?[432]==1048576,"Use actual resident bytes rather than physical footprint")
  check(SystemProcessOutput.residentMemory("178 -1")==nil,"Reject invalid memory")
  check(SystemProcessOutput.residentMemory("178 1\n178 2")==nil,"Reject duplicate resident memory records")
  let system=ProcessSample(pid:178,uid:88,start:1,startMicro:2,name:"WindowServer",memory:1,cpu:30,cpuNS:1,powerScore:40)
  let app=ProcessSample(pid:432,uid:UInt32(getuid()),start:1,startMicro:2,name:"Example",memory:1,cpu:10,cpuNS:1,powerScore:12)
  let groups=ProcessGrouping.groups([system,app])
  check(groups.contains {$0.name=="WindowServer"},"Keep system processes in the same process list")
  check(groups.max {($0.powerScore ?? 0)<($1.powerScore ?? 0)}?.name=="WindowServer","System processes participate in Top Drain by real score")
  check(groups.first {$0.name=="WindowServer"}?.representative.uid==88,"Preserve real process ownership")
  let live=await TelemetryCollector().sample(includeSystemMetrics:true)
  guard let server=live.processGroups.first(where:{$0.name=="WindowServer"}) else {fatalError("Live WindowServer is missing")}
  check(server.hasCPU && server.hasMemory && server.powerScore != nil,"Live system-owned process has CPU, resident memory and power score")
  check(server.representative.uid != getuid(),"System owner was not replaced with current user")
  print("PASS \(count) system process checks")
  print("WindowServer CPU:",server.cpu,"Power:",server.powerScore as Any,"Resident:",server.memory,"Owner:",server.representative.uid)
 }
}
