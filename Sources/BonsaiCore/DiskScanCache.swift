import Foundation
import Darwin

/// Saved measurements are display-only. Filesystem changes always use a new
/// full identity manifest; this cache can never authorize removal.
public struct DiskScanCache:Sendable {
    public let directory:URL
    private var file:URL {directory.appendingPathComponent("maps-v1.json")}
    private struct Archive:Codable {let version:Int;let scans:[DiskScan]}
    public init(directory:URL) {self.directory=physicalURL(directory)}
    public static var application:DiskScanCache {DiskScanCache(directory:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(AppIdentity.diskCachePath))}
    public func load(now:Date=Date())->[DiskScan] {
        guard safeParents(),let identity=try? Identity.read(file),identity.owner==getuid(),!identity.isDirectory,!identity.isSymlink,identity.size<=16_777_216,
              let data=try? Data(contentsOf:file),let archive=try? JSONDecoder().decode(Archive.self,from:data),archive.version==1,archive.scans.count<=8 else {return []}
        return archive.scans.filter {scan in
            let age=now.timeIntervalSince(scan.date)
            guard age.isFinite,age >= -60,age<7*86400,!scan.wasCancelled,scan.entries.count<=10_000,
                  scan.root.path.hasPrefix("/"),!scan.root.pathComponents.contains(".."),!scan.root.pathComponents.contains(".") else {return false}
            let allowed=Set(DiskExplorer.overviewLocations().map(\.path))
            return scan.entries.allSatisfy {entry in
                let belongs = scan.scope == .overview ? allowed.contains(entry.url.path) : entry.url.deletingLastPathComponent().path==scan.root.path
                guard belongs,entry.measurement.manifest.count<=1 else {return false}
                guard let old=entry.measurement.manifest[physicalURL(entry.url).path] else {return !entry.measurement.complete && entry.measurement.allocated==0}
                guard let current=try? Identity.read(entry.url) else {return false}
                return current.sameObject(as:old)
            }
        }
    }
    public func save(_ scans:[DiskScan]) {
        guard safeParents() else {return}
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            guard safeParents(),let identity=try? Identity.read(directory),identity.owner==getuid(),identity.isDirectory else {return}
            let keep=Array(scans.filter {!$0.wasCancelled && $0.entries.count<=10_000}.prefix(8))
            let data=try JSONEncoder().encode(Archive(version:1,scans:keep));guard data.count<=16_777_216 else {return}
            if let current=try? Identity.read(file),current.isSymlink || current.owner != getuid() {return}
            try data.write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } catch { /* A cache failure must never block Analyze. */ }
    }
    public func remove() {
        guard safeParents(),let identity=try? Identity.read(file),!identity.isSymlink,identity.owner==getuid() else {return}
        try? FileManager.default.removeItem(at:file)
    }
    private func safeParents()->Bool {
        var path=directory
        while path.path != "/" {
            if let identity=try? Identity.read(path),identity.isSymlink || !identity.isDirectory {return false}
            path.deleteLastPathComponent()
        }
        return true
    }
}
