import Foundation
import Darwin

public struct CommandResult: Codable, Sendable {
    public let status: Int32; public let output: String; public let standardOutput: String; public let standardError: String; public let timedOut: Bool; public let cancelled: Bool
    public init(status:Int32, output:String="", standardOutput:String="", standardError:String="", timedOut:Bool=false, cancelled:Bool=false) {
        self.status=status;self.output=output;self.standardOutput=standardOutput;self.standardError=standardError;self.timedOut=timedOut;self.cancelled=cancelled
    }
    public var succeeded: Bool { status == 0 && !timedOut && !cancelled }
}
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data(); private let limit:Int
    init(limit:Int=131072) {self.limit=limit}
    func add(_ d: Data) { lock.lock(); defer { lock.unlock() }; if data.count < limit { data.append(d.prefix(limit-data.count)) } }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data,as: UTF8.self) }
}
public enum CommandRunner {
    public static let allowed = ["/usr/bin/qlmanage","/usr/bin/mdutil","/usr/sbin/diskutil","/bin/launchctl","/usr/sbin/softwareupdate","/usr/bin/pmset","/opt/homebrew/bin/brew","/usr/local/bin/brew","/usr/bin/true","/usr/bin/false","/bin/sleep"]
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> CommandResult {
        guard allowed.contains(executable), FileManager.default.isExecutableFile(atPath: executable) else { throw BonsaiError.unavailable("Command is unavailable on this Mac: \(executable)") }
        return try await execute(executable,arguments,timeout:timeout)
    }
    static func systemProcessUsage() async throws -> CommandResult {
        // Apple's read-only monitor can inspect system tasks that this app
        // cannot query directly. -R disables expensive memory-map traversal.
        try await execute("/usr/bin/top",["-l","2","-s","1","-R","-n","4096","-stats","pid,cpu,power","-o","pid"],timeout:5,outputLimit:2_097_152)
    }
    static func systemResidentMemory() async throws -> CommandResult {
        try await execute("/bin/ps",["-axo","pid=,rss="],timeout:3,outputLimit:524_288)
    }
    static func processNetworkCounters() async throws -> CommandResult {
        try await execute("/usr/bin/nettop",["-P","-L","1","-n","-x","-J","bytes_in,bytes_out","-t","external"],timeout:3,outputLimit:2_097_152)
    }
    static func checkUpdatePackage(_ package:URL) async throws -> CommandResult {
        guard package.lastPathComponent=="Installer.pkg",package.deletingLastPathComponent().lastPathComponent.hasPrefix("Bonsai-installer-"),!(try Identity.read(package)).isSymlink else {throw BonsaiError.refused("Invalid update package path.")}
        return try await execute("/usr/sbin/pkgutil",["--check-signature",package.path],timeout:30)
    }
    static func attachUpdateImage(_ archive:URL,at mount:URL) async throws -> CommandResult {
        try validateUpdateMount(mount)
        guard archive.pathExtension=="dmg",!(try Identity.read(archive)).isSymlink else {throw BonsaiError.refused("Invalid update disk image.")}
        return try await execute("/usr/bin/hdiutil",["attach",archive.path,"-readonly","-nobrowse","-noautoopen","-mountpoint",mount.path,"-plist"],timeout:60)
    }
    static func detachUpdateImage(at mount:URL) async throws -> CommandResult {
        try validateUpdateMount(mount)
        return try await execute("/usr/bin/hdiutil",["detach",mount.path],timeout:20)
    }
    private static func validateUpdateMount(_ mount:URL) throws {
        guard mount.deletingLastPathComponent().path==physicalURL(FileManager.default.temporaryDirectory).path,
              mount.lastPathComponent.hasPrefix("Bonsai-update-volume-"),!(try Identity.read(mount)).isSymlink else {throw BonsaiError.refused("Invalid temporary update mount.")}
    }
    static func runProtection(_ script:URL,_ identifiers:[String]) async throws -> CommandResult {
        // Caller verifies pinned bytes; this capability accepts only classifier IDs.
        guard script.lastPathComponent=="protection.sh",identifiers.count<=512,identifiers.allSatisfy({$0.range(of:"^[A-Za-z0-9][A-Za-z0-9._+-]*$",options:.regularExpression) != nil}) else {throw BonsaiError.refused("Invalid Bonsai protection invocation.")}
        return try await execute("/bin/bash",[script.path]+identifiers,timeout:8)
    }
    static func runMaintenanceBackend(_ script:URL,action:String,helper:URL,timeout:TimeInterval) async throws -> CommandResult {
        guard script.lastPathComponent=="run.sh",MaintenanceBackend.actions.contains(action),FileManager.default.isExecutableFile(atPath:helper.path) else {throw BonsaiError.unavailable("Bonsai maintenance helper is unavailable.")}
        return try await execute("/bin/bash",[script.path,action],timeout:timeout,backendHelper:helper.path)
    }
    static func runBrewCatalog(_ executable:String) async throws -> CommandResult {
        guard ["/opt/homebrew/bin/brew","/usr/local/bin/brew"].contains(executable) else {throw BonsaiError.refused("Unsupported package manager.")}
        return try await execute(executable,["info","--cask","--json=v2","--installed"],timeout:90,outputLimit:2_097_152)
    }
    private static func execute(_ executable:String,_ arguments:[String],timeout:TimeInterval,outputLimit:Int=131072,backendHelper:String?=nil) async throws -> CommandResult {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        if let helper=backendHelper {
            // Never accept upstream test/probe/path overrides from a parent shell.
            environment=environment.filter { ["HOME","USER","LOGNAME","TMPDIR","LANG"].contains($0.key) }
            environment["BONSAI_TRASH_HELPER"]=helper
        }
        environment.removeValue(forKey:"BASH_ENV");environment.removeValue(forKey:"ENV");environment["PATH"]="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"; environment["HOMEBREW_NO_ANALYTICS"] = "1"; environment["LC_ALL"] = "C"; process.environment = environment
        let pipe = Pipe(); let errors = Pipe(); let buffer = OutputBuffer(limit:outputLimit); let errorBuffer = OutputBuffer()
        process.standardOutput = pipe; process.standardError = errors; process.standardInput = FileHandle.nullDevice
        let descriptor = pipe.fileHandleForReading.fileDescriptor; let errorDescriptor = errors.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor,F_SETFL,O_NONBLOCK); _ = fcntl(errorDescriptor,F_SETFL,O_NONBLOCK)
        func drainDescriptor(_ fd: Int32,_ target: OutputBuffer) {
            var chunk = [UInt8](repeating:0,count:8192)
            for _ in 0..<64 { let count = read(fd,&chunk,chunk.count); if count <= 0 { break }; target.add(Data(chunk.prefix(count))) }
        }
        func drain() { drainDescriptor(descriptor,buffer); drainDescriptor(errorDescriptor,errorBuffer) }
        try Task.checkCancellation(); try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0,timeout); var timedOut = false; var cancelled = false
        // A cancelled caller still yields while the child receives TERM/KILL.
        func pause() async { await Task.detached { try? await Task.sleep(nanoseconds:25_000_000) }.value }
        while process.isRunning {
            drain()
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                cancelled = Task.isCancelled; timedOut = !cancelled; if getpgid(process.processIdentifier)==process.processIdentifier {kill(-process.processIdentifier,SIGTERM)} else {process.terminate()}
                let grace = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { drain(); await pause() }
                if process.isRunning { kill(getpgid(process.processIdentifier)==process.processIdentifier ? -process.processIdentifier : process.processIdentifier, SIGKILL) }
                break
            }
            await pause()
        }
        // Foundation waitUntilExit can deadlock an async executor after cancellation.
        // Await the termination notification without blocking its delivery thread.
        let exitDeadline = ProcessInfo.processInfo.systemUptime + 2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < exitDeadline { drain(); await pause() }
        guard !process.isRunning else { throw BonsaiError.unavailable("The child did not acknowledge termination. Check its source app before retrying.") }
        drain()
        try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close(); try? errors.fileHandleForReading.close(); try? errors.fileHandleForWriting.close()
        return CommandResult(status: process.terminationStatus, output: buffer.string + errorBuffer.string, standardOutput: buffer.string, standardError: errorBuffer.string, timedOut: timedOut, cancelled: cancelled)
    }
}
public struct MaintenanceTask: Identifiable, Sendable {
    public let id: String; public let title: String; public let explanation: String; public let executable: String; public let arguments: [String]
    public let verification: [String]; public let timeout: TimeInterval; public let prerequisite: String
    public var preview: String { ([executable] + arguments).joined(separator: " ") }
    public static let catalog: [MaintenanceTask] = [
        .init(id: "quicklook", title: "Refresh Quick Look", explanation: "Rebuild thumbnail caches when Finder previews are missing or incorrect. Thumbnails regenerate as you browse.", executable: "/usr/bin/qlmanage", arguments: ["-r","cache"], verification: ["-m","plugins"], timeout: 30, prerequisite: "Save work. No administrator access required."),
        .init(id: "generators", title: "Reload preview generators", explanation: "Reload the Quick Look generator registry after adding or removing preview extensions.", executable: "/usr/bin/qlmanage", arguments: ["-r"], verification: ["-m","plugins"], timeout: 30, prerequisite: "No administrator access required."),
        .init(id: "spotlight", title: "Check Spotlight", explanation: "Inspect indexing state to diagnose search problems. Read-only; no index deletion.", executable: "/usr/bin/mdutil", arguments: ["-s","/"], verification: ["-s","/"], timeout: 20, prerequisite: "Read-only. The system may restrict indexing information."),
        .init(id: "disk", title: "Verify startup volume", explanation: "Ask Disk Utility to verify filesystem integrity. Can take several minutes and increase disk activity. Repairs are performed separately in Disk Utility or Recovery.", executable: "/usr/sbin/diskutil", arguments: ["verifyVolume","/"], verification: ["info","/"], timeout: 180, prerequisite: "Save work; keep the Mac connected to power. Disk Utility may require authorization."),
        .init(id: "power", title: "Diagnose power assertions", explanation: "Identify services preventing sleep so you can close or configure them. Read-only.", executable: "/usr/bin/pmset", arguments: ["-g","assertions"], verification: ["-g","assertions"], timeout: 15, prerequisite: "Read-only. No administrator access required.")
    ] + maintenanceTasks
    private static let maintenanceTasks:[MaintenanceTask]=[
        maintenance("saved_state_cleanup","Trim old application states","Move inactive apps’ saved states older than 30 days to Trash. Restore them from Trash if needed.",60),
        maintenance("fix_broken_configs","Repair corrupt preferences","Bonsai finds invalid third-party preference files; Bonsai verifies them again and moves eligible files to Trash. Apple preferences and running apps are excluded.",60),
        maintenance("login_items_audit","Audit login items","Check login entries for missing applications through Bonsai’s read-only inventory.",45),
        maintenance("audit_system_maintenance","Check DNS maintenance","Administrator DNS refresh is diagnosed only; it is not run without authorization.",60),
        maintenance("audit_network_optimization","Check network cache refresh","Preview DNS and mDNS maintenance without restarting network services.",60),
        maintenance("audit_network_stack_optimize","Check network stack repair","Preview route and ARP maintenance without interrupting connections.",60),
        maintenance("audit_disk_permissions_repair","Check home folder permissions","Inspect Bonsai permission diagnostics without changing ownership or permissions.",60),
        maintenance("audit_spotlight_orphan_rules_cleanup","Check obsolete Spotlight rules","Preview rules for missing applications without rewriting search settings.",60),
        maintenance("shared_file_list_repair","Repair corrupt Finder lists","Move invalid shared-file lists to Trash for recovery. Healthy lists and application recent-document lists stay.",60),
        maintenance("audit_quarantine_cleanup","Check download history","Preview Bonsai download-history maintenance. Existing download history is retained.",60),
        maintenance("audit_notification_cleanup","Check notification history","Preview old notification maintenance without deleting notifications.",60),
        maintenance("audit_coreduet_cleanup","Check usage databases","Preview Bonsai usage database maintenance without deleting usage history.",60),

        maintenance("cache_refresh","Refresh Finder caches","Refresh Quick Look thumbnails and retire generated icon caches to Trash. macOS recreates them as needed.",45),
        maintenance("sqlite_vacuum","Compact application databases","Bonsai checks free pages and integrity before compacting Mail, Messages and Safari databases. Skips running apps and databases over 100 MB; Full Disk Access may be needed.",120),
        maintenance("launch_agents_cleanup","Check broken background services","Report user LaunchAgents whose executables are missing. Keeps their configuration and current state unchanged.",45),
        maintenance("spotlight_index_optimize","Check Spotlight performance","Measure indexing/search responsiveness. Index rebuilds require administrator access and are skipped by the background runner.",40),
        maintenance("periodic_maintenance","Check periodic maintenance","Run only when stale and supported. Skips administrator work; newer macOS versions no longer provide periodic.",20),
        maintenance("prevent_network_dsstore","Reduce Finder metadata files","Enable Finder preferences to avoid .DS_Store files on network and USB volumes. Persistent, reversible preference change.",20),
        maintenance("legacy_overrides_audit","Restore legacy system defaults","Remove explicit App Nap and disk-image verification overrides left by older tweak tools. Restores macOS defaults.",30)
    ]
    private static func maintenance(_ id:String,_ title:String,_ explanation:String,_ timeout:TimeInterval)->MaintenanceTask {
        .init(id:id,title:title,explanation:explanation,executable:"Bonsai",arguments:["optimize",id],verification:[],timeout:timeout,prerequisite:id=="sqlite_vacuum" ? "Close Mail, Safari and Messages. Full Disk Access may be needed." : "Runs locally as your current user. Administrator operations are skipped.")
    }
    public static let groups=["Additional checks","Finder previews","Application databases","System checks","Finder preferences","Disk health"]
    public var group:String { if id.hasPrefix("audit_") {return "Additional checks"}; switch id { case "quicklook","generators","cache_refresh":return "Finder previews";case "sqlite_vacuum","saved_state_cleanup","fix_broken_configs","shared_file_list_repair":return "Application databases";case "spotlight","power","login_items_audit","launch_agents_cleanup","spotlight_index_optimize","periodic_maintenance":return "System checks";case "prevent_network_dsstore","legacy_overrides_audit":return "Finder preferences";default:return "Disk health" } }
    public var symbol:String { switch id { case "quicklook":return "photo";case "generators":return "puzzlepiece.extension";case "spotlight":return "magnifyingglass";case "power":return "moon";default:return "internaldrive" } }
    public var readOnly:Bool { id.hasPrefix("audit_") || ["login_items_audit","spotlight","power","disk","launch_agents_cleanup","spotlight_index_optimize","periodic_maintenance"].contains(id) }
    public var recommended:Bool { id.hasPrefix("audit_") || ["shared_file_list_repair","saved_state_cleanup","fix_broken_configs","login_items_audit","cache_refresh","sqlite_vacuum","launch_agents_cleanup","spotlight_index_optimize","periodic_maintenance","spotlight","power"].contains(id) }
    public var available:Bool { executable=="Bonsai" || FileManager.default.isExecutableFile(atPath:executable) }
    public var durationLabel:String { id == "disk" ? "Up to 3 min" : "Up to \(Int(timeout)) sec" }
    public typealias Executor = @Sendable (String,[String],TimeInterval) async throws -> CommandResult
    public func perform(using execute:Executor = { try await CommandRunner.run($0,$1,timeout:$2) }) async -> ItemOutcome {
        if executable=="Bonsai" {return await MaintenanceBackend.perform(self)}
        var operationOutput=""
        do {
            try Task.checkCancellation()
            let result = try await execute(executable,arguments,timeout)
            operationOutput=result.output
            if !result.succeeded { return ItemOutcome(title: title,path: preview,status: result.cancelled ? "Cancelled" : "Failed", detail: (result.timedOut ? "Timed out. " : "Exit \(result.status). ") + result.output) }
            if Task.isCancelled { return ItemOutcome(title:title,path:preview,status:"Cancelled",detail:"Operation finished; verification did not start.\nOperation output:\n\(operationOutput)") }
            let verify = try await execute(executable,verification,20)
            if verify.cancelled || Task.isCancelled { return ItemOutcome(title:title,path:preview,status:"Cancelled",detail:"Operation finished, but the post-check was cancelled.\nOperation output:\n\(result.output)\nPost-check:\n\(verify.output)") }
            return ItemOutcome(title: title,path: preview,status: verify.succeeded ? "Completed" : "Verification failed",detail: "Operation output:\n\(result.output)\nPost-check:\n\(verify.timedOut ? "Timed out. " : "")\(verify.output)\nCommand completion is verified; cache regeneration and filesystem repairs may require further checks in Finder or Disk Utility.")
        } catch { return ItemOutcome(title: title,path: preview,status: error is CancellationError ? "Cancelled" : "Failed",detail: error.localizedDescription+(operationOutput.isEmpty ? "" : "\nOperation output:\n\(operationOutput)")) }
    }
}

/// Sequential, bounded tasks. Cancellation records every remaining item as skipped
/// and never starts another command, even when an injected worker ignores it.
public enum MaintenanceRunner {
    /// The direct Optimize action is independent of optional/custom selection.
    /// Only supported routine commands are eligible; disk verification is opt-in.
    public static var quickPlan:[MaintenanceTask] {
        MaintenanceTask.catalog.filter { $0.recommended && $0.available }
    }
    public static func plan(selected:Set<String>) -> [MaintenanceTask] {
        MaintenanceTask.catalog.filter { selected.contains($0.id) }
    }
    public static func run(_ tasks:[MaintenanceTask],
        progress:@Sendable (Int,MaintenanceTask,[ItemOutcome]) async -> Void = { _,_,_ in },
        execute:@Sendable (MaintenanceTask) async -> ItemOutcome = { await $0.perform() }) async -> [ItemOutcome] {
        var outcomes:[ItemOutcome]=[]
        var visited=Set<String>()
        for task in tasks where visited.insert(task.id).inserted {
            if Task.isCancelled {
                outcomes.append(ItemOutcome(title:task.title,path:task.preview,status:"Skipped",detail:"Cancelled before this task started; no command was run."))
                continue
            }
            await progress(outcomes.count,task,outcomes)
            // Progress callbacks may suspend or cancel the caller.
            if Task.isCancelled {
                outcomes.append(ItemOutcome(title:task.title,path:task.preview,status:"Skipped",detail:"Cancelled before this task started; no command was run."))
                continue
            }
            outcomes.append(await execute(task))
        }
        return outcomes
    }
}
