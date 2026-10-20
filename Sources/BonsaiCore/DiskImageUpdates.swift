import Foundation

/// Mount publisher disk images read-only and copy only the uniquely matching app.
/// Installer packages, scripts and links to other volumes are never followed.
public enum DiskImageUpdates {
    public static func matchingApp(in root:URL,bundleID:String) throws -> URL {
        var queue=[(root,0)],matches:[URL]=[],count=0
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while let (folder,depth)=queue.popLast() {
            try Task.checkCancellation()
            guard count<2048,ProcessInfo.processInfo.systemUptime<deadline else {throw BonsaiError.refused("Disk image contains too many entries.")}
            for entry in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
                count+=1
                guard count<=2048 else {throw BonsaiError.refused("Disk image contains too many entries.")}
                let identity=try Identity.read(entry)
                guard identity.isDirectory,!identity.isSymlink else {continue}
                if entry.pathExtension=="app" {
                    if Bundle(url:entry)?.bundleIdentifier==bundleID {matches.append(entry)}
                } else if depth<3 {queue.append((entry,depth+1))}
            }
        }
        guard matches.count==1,let candidate=matches.first else {throw BonsaiError.refused("Disk image must contain exactly one app matching the installed bundle identifier.")}
        return candidate
    }
    public static func extract(_ archive:URL,to destination:URL,bundleID:String) async throws {
        let mount=physicalURL(FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-update-volume-"+UUID().uuidString))
        try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let result:Result<Void,Error>
        do {
            let attached=try await CommandRunner.attachUpdateImage(archive,at:mount)
            guard attached.succeeded else {throw BonsaiError.unavailable("Could not open the update disk image. "+attached.standardError)}
            try Task.checkCancellation()
            let candidate=try matchingApp(in:mount,bundleID:bundleID)
            // A bounded inspection avoids expanding a small compressed DMG into
            // an unexpectedly huge bundle. Walk does not follow symbolic links.
            let measurement=try FileScanner.measure(candidate,limits:ScanLimits(nodes:200_000,seconds:20))
            guard measurement.complete,measurement.logical<=4_294_967_296 else {throw BonsaiError.refused("Disk image app is too large or could not be inspected completely.")}
            try FileManager.default.copyItem(at:candidate,to:destination.appendingPathComponent(candidate.lastPathComponent))
            result = .success(())
        } catch {result = .failure(error)}
        // Cleanup must run even when the caller cancelled the download/update.
        let detached=await Task.detached(priority:.utility) {try? await CommandRunner.detachUpdateImage(at:mount)}.value
        if detached?.succeeded==true {try? FileManager.default.removeItem(at:mount)}
        else {
            // Failed attach may leave an ordinary empty directory; never remove
            // a mounted volume recursively if macOS refused to detach it.
            if (try? FileManager.default.contentsOfDirectory(atPath:mount.path).isEmpty)==true {try? FileManager.default.removeItem(at:mount)}
            if case .success = result {throw BonsaiError.unavailable("Update image could not be ejected. Nothing was replaced. Eject "+mount.path+" and retry.")}
        }
        try result.get()
    }
}
