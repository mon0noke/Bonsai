import Foundation
import CryptoKit

/// Actual pinned upstream handlers, with an allowlisted adapter and native Trash.
public enum MaintenanceBackend {
    public static let actions:Set<String>=["saved_state_cleanup","fix_broken_configs","login_items_audit","audit_system_maintenance","audit_network_optimization","audit_network_stack_optimize","audit_disk_permissions_repair","audit_spotlight_orphan_rules_cleanup","shared_file_list_repair","audit_quarantine_cleanup","audit_notification_cleanup","audit_coreduet_cleanup","cache_refresh","sqlite_vacuum","prevent_network_dsstore","legacy_overrides_audit","launch_agents_cleanup","spotlight_index_optimize","periodic_maintenance"]
    private static let manifestHash="56921267b1376ec5cf69018943ee2cb3bb24b15cacc38a40be0aafb654ea0c83"
    private struct Manifest:Decodable {let revision:String;let files:[String:String]}
    public static func validatedScript(directory:URL?=nil) throws -> URL {
        guard let root=directory ?? Bundle.main.resourceURL?.appendingPathComponent("MaintenanceBackend") else {throw BonsaiError.unavailable("Bonsai maintenance backend is missing. Reinstall Bonsai.")}
        let file=root.appendingPathComponent("Manifest.json")
        guard !(try Identity.read(file)).isSymlink else {throw BonsaiError.refused("Maintenance manifest was replaced.")}
        let data=try Data(contentsOf:file)
        guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==manifestHash else {throw BonsaiError.refused("Maintenance manifest integrity failed.")}
        let manifest=try JSONDecoder().decode(Manifest.self,from:data)
        guard manifest.revision==ProtectionBackend.revision else {throw BonsaiError.refused("Unexpected Bonsai revision.")}
        for (name,hash) in manifest.files {
            guard !name.hasPrefix("/"),!name.split(separator:"/").contains("..") else {throw BonsaiError.refused("Invalid backend path.")}
            var parent=root.appendingPathComponent(name)
            while parent.path != root.deletingLastPathComponent().path {
                guard !(try Identity.read(parent)).isSymlink else {throw BonsaiError.refused("Maintenance resource is a symbolic link.")}
                if parent==root {break};parent.deleteLastPathComponent()
            }
            let bytes=try Data(contentsOf:root.appendingPathComponent(name))
            guard bytes.count<=2_097_152,SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==hash else {throw BonsaiError.refused("Maintenance backend integrity failed. Reinstall Bonsai.")}
        }
        return root.appendingPathComponent("run.sh")
    }
    public static func parse(_ result:CommandResult,action:String,title:String,path:String) -> ItemOutcome {
        let output=result.output.replacingOccurrences(of:"\u{001B}\\[[0-9;]*[a-zA-Z]",with:"",options:.regularExpression)
        if !result.succeeded {return ItemOutcome(title:title,path:path,status:result.cancelled ? "Cancelled" : "Failed",detail:(result.timedOut ? "Timed out. " : "Exit \(result.status). ")+output)}
        let records=result.standardOutput.split(separator:"\n").filter {$0.hasPrefix("BONSAI_TASK_RESULT\t")}
        guard records.count==1 else {return ItemOutcome(title:title,path:path,status:"Verification failed",detail:"Bonsai returned no unique task result.\n"+output)}
        let fields=records[0].split(separator:"\t",omittingEmptySubsequences:false)
        let statuses=["applied":"Completed","unchanged":"Unchanged","skipped":"Skipped","unavailable":"Unavailable","attention":"Needs attention","failed":"Failed"]
        guard fields.count==3,fields[1]==action,let status=statuses[String(fields[2])] else {return ItemOutcome(title:title,path:path,status:"Verification failed",detail:"Bonsai returned an invalid task result.\n"+output)}
        let detail=output.components(separatedBy:"\n").filter {!$0.hasPrefix("BONSAI_TASK_RESULT\t")}.joined(separator:"\n")
        return ItemOutcome(title:title,path:path,status:status,detail:"Bonsai \(ProtectionBackend.revision.prefix(8)) · \(action)\n"+detail)
    }
    public static func databasePreflight(home:URL=FileManager.default.homeDirectoryForCurrentUser) throws {
        // Do not interpret an inaccessible directory as "no databases found".
        let library=home.appendingPathComponent("Library")
        for name in ["Mail","Messages","Safari"] {
            let url=library.appendingPathComponent(name)
            do {
                var ancestor=url
                while ancestor.path != home.deletingLastPathComponent().path {
                    let part=try Identity.read(ancestor)
                    guard !part.isSymlink else {throw BonsaiError.refused("Database path contains a symbolic link.")}
                    if ancestor==home {break};ancestor.deleteLastPathComponent()
                }
                let identity=try Identity.read(url)
                guard identity.owner==getuid(),identity.isDirectory,!identity.isSymlink else {throw BonsaiError.refused("Database folder ownership or link is unsupported: "+url.path)}
                let entries=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil)
                guard entries.count<=10_000 else {throw BonsaiError.refused("Database folder is too large to inspect. Open the application to maintain it.")}
                for entry in entries where entry.pathExtension=="db" || (name=="Mail" && entry.lastPathComponent.hasPrefix("V")) {
                    let child=try Identity.read(entry)
                    guard !child.isSymlink,child.owner==getuid(),child.isDirectory || child.links==1 else {throw BonsaiError.refused("Database path is linked or belongs to another user: "+entry.path)}
                    if name=="Mail" {
                        let data=entry.appendingPathComponent("MailData")
                        do {
                            let dir=try Identity.read(data)
                            guard dir.owner==getuid(),dir.isDirectory,!dir.isSymlink else {throw BonsaiError.refused("Mail database folder is linked or belongs to another user.")}
                            for db in try FileManager.default.contentsOfDirectory(at:data,includingPropertiesForKeys:nil) where db.lastPathComponent.hasPrefix("Envelope Index") {
                                let id=try Identity.read(db)
                                guard !id.isSymlink,!id.isDirectory,id.links==1,id.owner==getuid() else {throw BonsaiError.refused("Mail database is linked or has unsupported ownership.")}
                            }
                        } catch let error as NSError where error.domain==NSPOSIXErrorDomain && error.code==2 {continue}
                    }
                }
            } catch let error as NSError where error.domain==NSPOSIXErrorDomain && error.code==2 {continue}
        }
    }
    public static func perform(_ task:MaintenanceTask) async -> ItemOutcome {
        do {
            try Task.checkCancellation()
            guard actions.contains(task.id) else {throw BonsaiError.refused("Unsupported Bonsai operation.")}
            if task.id=="sqlite_vacuum" {try databasePreflight()}
            if task.id=="shared_file_list_repair" {
                let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
                do {let identity=try Identity.read(folder);guard identity.owner==getuid(),identity.isDirectory,!identity.isSymlink else {throw BonsaiError.refused("Finder list folder ownership or link is unsupported.")};_ = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)}
                catch let error as NSError where error.domain==NSPOSIXErrorDomain && error.code==2 {}
            }
            let script=try validatedScript()
            let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BonsaiMaintenanceTrash")
            let result=try await CommandRunner.runMaintenanceBackend(script,action:task.id,helper:helper,timeout:task.timeout)
            return parse(result,action:task.id,title:task.title,path:task.preview)
        } catch {return ItemOutcome(title:task.title,path:task.preview,status:error is CancellationError ? "Cancelled" : FileAccess.isPermission(error) ? "Needs access" : "Failed",detail:error.localizedDescription+(FileAccess.isPermission(error) ? "\nEnable Bonsai in Privacy Settings > Full Disk Access and restart it, then retry. No repair was applied by this task." : ""))}
    }
}
