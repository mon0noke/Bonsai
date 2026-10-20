import Foundation
import Darwin

public enum TrashPurge {
    // This API only accepts reviewed direct children of the user's Trash.
    // Injected roots/removers exist for isolated fixtures, never shell deletion.
    public static func perform(_ items:[ReviewItem],root:URL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),exclusions:[String]=[],confirmed:Bool=false,dryRun:Bool=false,remover:@Sendable(URL)throws->Void={try FileManager.default.removeItem(at:$0)}) async -> [ItemOutcome] {
        var outcomes:[ItemOutcome]=[]
        let root=physicalURL(root)
        for item in items {
            var deletionStarted=false
            do {
                try Task.checkCancellation()
                guard dryRun || confirmed else {throw BonsaiError.refused("Permanent deletion requires explicit confirmation.")}
                guard root.lastPathComponent==".Trash",item.category=="Trash",physicalURL(item.url.deletingLastPathComponent())==root,item.readOnlyReason==nil else {throw BonsaiError.refused("Only reviewed direct children of Trash can be emptied.")}
                let parent=try Identity.read(root)
                guard parent.owner==getuid(),parent.isDirectory,!parent.isSymlink,parent.sameObject(as:item.parentIdentity) else {throw BonsaiError.changed("Trash directory changed or is not owned by this user.")}
                let policy=PathPolicy(roots:[root],protected:exclusions.map {URL(fileURLWithPath:$0)})
                guard let expected=item.measurement.manifest[item.id],item.measurement.complete else {throw BonsaiError.refused("Trash item is incompletely measured. Resolve access and rescan.")}
                try policy.validate(item.url,expected:expected)
                let current=try FileScanner.measure(item.url)
                guard current.complete,current.manifest==item.measurement.manifest else {throw BonsaiError.changed("Trash contents changed since review. Scan again.")}
                guard current.manifest.allSatisfy({$0.value.owner==getuid()}) else {throw BonsaiError.refused("Trash item contains files owned by another user.")}
                try Task.checkCancellation();try policy.validate(item.url,expected:expected)
                guard try Identity.read(root).sameObject(as:item.parentIdentity) else {throw BonsaiError.changed("Trash directory changed. Scan again.")}
                if dryRun {outcomes.append(ItemOutcome(title:item.title,path:item.id,status:"Preview",detail:"Permanent-deletion preview validated. No files changed."));continue}
                deletionStarted=true;try remover(item.url)
                guard try Identity.read(root).sameObject(as:item.parentIdentity) else {throw BonsaiError.changed("Trash directory changed after deletion. Refresh to verify.")}
                do {
                    _=try Identity.read(item.url)
                    throw BonsaiError.unavailable("The Trash item still exists after deletion. Refresh to inspect the outcome.")
                } catch {guard FileAccess.status(error) == .missing else {throw error}}
                outcomes.append(ItemOutcome(title:item.title,path:item.id,status:"Deleted",detail:item.measurement.label+" permanently deleted from Trash. No Put Back recovery is available. Hardlinks and APFS snapshots can retain storage."))
            } catch {outcomes.append(ItemOutcome(title:item.title,path:item.id,status:deletionStarted ? "Partial failure" : error is CancellationError ? "Cancelled":"Skipped",detail:deletionStarted ? "Deletion began but could not be fully verified. Some contents may have been removed. Refresh Trash to inspect the remaining item. "+error.localizedDescription : error.localizedDescription))}
        }
        return outcomes
    }
}
