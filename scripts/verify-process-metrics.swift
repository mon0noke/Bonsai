import Foundation
import BonsaiCore

@main struct ProcessMetricsVerify {
    static func main() async throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        check(ProcessMetricRates.watts(previous:10,current:2_000_000_010,elapsed:2)==1,"Nanoules convert to watts using actual elapsed time")
        check(ProcessMetricRates.watts(previous:10,current:10,elapsed:2)==0,"An idle interval is zero")
        check(ProcessMetricRates.watts(previous:10,current:9,elapsed:2)==nil,"Reset counters are unknown")
        check(ProcessMetricRates.watts(previous:0,current:100,elapsed:0)==nil,"No zero interval")
        check(ProcessMetricRates.watts(previous:0,current:100,elapsed:30)==nil,"No stale rates after sleep")
        let csv=",bytes_in,bytes_out,\nBrowser.Helper.123,2000,3000,\nName,with,commas.456,40,90,\n"
        let parsed=ProcessMetricRates.networkCounters(csv)
        check(parsed?.count==2,"Process names and comma-safe parsing")
        check(parsed?[123]?.0==2000 && parsed?[123]?.1==3000,"Inbound and outbound kept separate")
        check(parsed?[456]?.1==90,"PID parsed from rightmost dot")
        check(ProcessMetricRates.networkCounters("unexpected output")==nil,"No fabricated zero readings on unsupported output")
        check(ProcessMetricRates.networkCounters(",bytes_in,bytes_out,\nApp.1,1,2,\nApp.1,3,4,")==nil,"Duplicate records rejected")
        check(ProcessMetricRates.networkCounters(",bytes_in,bytes_out,\nApp.1,invalid,2,")==nil,"Malformed counters rejected")
        func process(_ pid:Int32,_ app:String,_ watts:Double?,_ down:Double?,_ up:Double?)->ProcessSample {
            ProcessSample(pid:pid,uid:501,start:1,startMicro:0,name:app,memory:1,cpu:1,cpuNS:1,executable:"/Applications/"+app+".app/Contents/MacOS/"+app,powerScore:watts,powerWatts:watts,networkDownload:down,networkUpload:up)
        }
        let groups=ProcessGrouping.groups([process(1,"A",1,20,30),process(2,"A",2,40,50),process(3,"B",nil,nil,nil),process(4,"C",0.5,1,2)])
        let a=groups.first {$0.name=="A"}!
        check(a.powerWatts==3 && a.powerComplete,"App power includes helpers")
        check(a.networkDownload==60 && a.networkUpload==80 && a.networkComplete,"App traffic includes helpers")
        for ascending in [true,false] {
            check(ProcessGrouping.presented(groups,query:"",sort:.power,ascending:ascending,pinned:[]).last?.name=="B","Unavailable power remains last")
            check(ProcessGrouping.presented(groups,query:"",sort:.network,ascending:ascending,pinned:[]).last?.name=="B","Unavailable traffic remains last")
        }
        let partial=ProcessGrouping.groups([process(10,"A",1,20,30),process(11,"A",nil,nil,nil)])[0]
        check(partial.powerWatts==1 && !partial.powerComplete,"Partial power marked incomplete")
        check(partial.networkDownload==20 && !partial.networkComplete,"Partial network marked incomplete")
        print("PASS \(checks) process power/network checks")
    }
}
