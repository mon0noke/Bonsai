import Foundation
import CBonsai

public struct ProcessDetails:Sendable {
    public let identity:String
    public let sampledAt:Date
    public let threads:UInt32?
    public let openFiles:UInt32?
    public let bytesRead:UInt64?
    public let bytesWritten:UInt64?
    public let workingDirectory:String?
    public let user:String?
}
public actor ProcessDetailCollector {
    public init() {}
    public func read(_ selected:ProcessSample)->ProcessDetails? {
        guard !Task.isCancelled else {return nil}
        var d=bonsai_process_detail()
        guard bonsai_process_details(selected.pid,&d) != 0,
              d.identity.uid==selected.uid,d.identity.start_sec==selected.start,d.identity.start_usec==selected.startMicro,!Task.isCancelled else {return nil}
        let cwd=withUnsafePointer(to:&d.cwd) {$0.withMemoryRebound(to:CChar.self,capacity:1024) {String(cString:$0)}}
        let user=withUnsafePointer(to:&d.user) {$0.withMemoryRebound(to:CChar.self,capacity:256) {String(cString:$0)}}
        return ProcessDetails(identity:selected.id,sampledAt:Date(),threads:d.threads_valid != 0 ? d.threads : nil,openFiles:d.files_valid != 0 ? d.open_files : nil,bytesRead:d.io_valid != 0 ? d.bytes_read : nil,bytesWritten:d.io_valid != 0 ? d.bytes_written : nil,workingDirectory:d.cwd_valid != 0 && !cwd.isEmpty ? cwd : nil,user:user.isEmpty ? nil : user)
    }
}
public enum ProcessInspection {
    // A relaunched app can share its group ID. Never silently target its new PID identity.
    public static func liveGroup(_ initial:ProcessGroup,in groups:[ProcessGroup])->ProcessGroup? {
        groups.first {$0.id==initial.id && $0.members.contains {$0.id==initial.representative.id && $0.uid==initial.representative.uid}}
    }
    public static func parents(of selected:ProcessSample,in processes:[ProcessSample])->[ProcessSample] {
        let byPID=Dictionary(processes.map {($0.pid,$0)},uniquingKeysWith: {first,_ in first})
        var result=[ProcessSample]();var current=selected;var seen:Set<Int32>=[selected.pid]
        for _ in 0..<16 {
            guard let parent=byPID[current.parentPID],!seen.contains(parent.pid),
                  parent.start<current.start || parent.start==current.start && parent.startMicro<=current.startMicro else {break}
            seen.insert(parent.pid);result.append(parent);current=parent
        }
        return result.reversed()
    }
}
public struct ActivityCounts:Sendable {
    public let trashMoves:Int
    public let applications:Int
    public let maintenanceTasks:Int
    public init(entries:[AuditEntry]) {
        let trashed=entries.flatMap(\.outcomes).filter {$0.status=="Trashed"}
        trashMoves=trashed.count
        applications=trashed.filter {$0.path.hasSuffix(".app")}.count
        maintenanceTasks=entries.filter {$0.operation=="Maintenance"}.flatMap(\.outcomes).filter {$0.status=="Completed"}.count
    }
}
