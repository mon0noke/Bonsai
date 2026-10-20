import Foundation

/// A Finder-style move of one explicitly chosen item. Moving the directory itself
/// does not follow links or require a complete recursive size measurement.
public struct DiskTrashRequest:Sendable {
    public let entry:DiskEntry
    public let identity:Identity
    public let parent:Identity
    public init(_ entry:DiskEntry) throws {
        self.entry=entry
        guard let identity=entry.measurement.manifest[physicalURL(entry.url).path] else {
            throw BonsaiError.unavailable("This item was not measured. Refresh this folder first.")
        }
        self.identity=identity
        parent=try Identity.read(physicalURL(entry.url).deletingLastPathComponent())
    }
}
public enum DiskTrash {
    public static func perform(_ request:DiskTrashRequest,policy:PathPolicy = .standard,runningApplications:@Sendable ()->[URL] = {[]},mover:@Sendable (URL)throws->URL? = {try TrashService.systemTrash($0)}) -> ItemOutcome {
        let entry=request.entry,url=physicalURL(entry.url)
        do {
            try Task.checkCancellation()
            try policy.validate(url,expected:request.identity)
            guard try Identity.read(url.deletingLastPathComponent()).sameObject(as:request.parent) else {
                throw BonsaiError.changed("This folder changed. Refresh and try again.")
            }
            guard !runningApplications().contains(where:{within(physicalURL($0).path,url.path)}) else {
                throw BonsaiError.refused("Quit the application in this item before moving it to Trash.")
            }
            try Task.checkCancellation()
            try policy.validate(url,expected:request.identity)
            let destination=try mover(url)
            guard (try? Identity.read(url)).map({!$0.sameObject(as:request.identity)}) ?? true else {throw BonsaiError.changed("The item remains in its original location. The move was not completed.")}
            return ItemOutcome(title:url.lastPathComponent,path:url.path,status:"Trashed",detail:"\(entry.label) moved to Trash. Restore it from Trash in Finder. Space is released when Trash is emptied; shared storage may remain.",recovery:destination?.path)
        } catch {
            return ItemOutcome(title:url.lastPathComponent,path:url.path,status:error is CancellationError ? "Cancelled" : "Skipped",detail:error.localizedDescription)
        }
    }
}
