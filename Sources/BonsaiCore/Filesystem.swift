import Foundation
import Darwin

public enum BonsaiError: LocalizedError {
    case refused(String), changed(String), unavailable(String)
    public var errorDescription: String? { switch self { case .refused(let s), .changed(let s), .unavailable(let s): return s } }
}
// Foundation standardization rewrites /private/var to /var on macOS.
// Expand only Apple's fixed, root-owned aliases; retain all user symlinks for validation.
public func physicalURL(_ url: URL) -> URL {
    for prefix in ["/var", "/tmp", "/etc"] where within(url.path,prefix) {
        return URL(fileURLWithPath:"/private" + url.path)
    }
    return url
}
public func within(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
public func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file) }
public struct Identity: Codable, Equatable, Sendable {
    public let device: Int32; public let inode: UInt64; public let owner: UInt32
    public let mode: UInt16; public let size: Int64; public let modified: Int64; public let nanos: Int64
    public let links: UInt16
    public var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    public var isSymlink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    public func sameObject(as other: Identity) -> Bool { device == other.device && inode == other.inode && owner == other.owner && mode == other.mode }
    public static func read(_ url: URL) throws -> Identity {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo:[NSFilePathErrorKey:url.path]) }
        return Identity(device: s.st_dev, inode: s.st_ino, owner: s.st_uid, mode: s.st_mode, size: s.st_size, modified: Int64(s.st_mtimespec.tv_sec), nanos: Int64(s.st_mtimespec.tv_nsec), links: s.st_nlink)
    }
}
public struct Measurement: Codable, Sendable {
    public init() {}
    public var logical: UInt64 = 0; public var allocated: UInt64 = 0; public var files = 0
    public var complete = true; public var issues: [String] = []; public var manifest: [String: Identity] = [:]
    public var accessDeniedPaths:[String]?
    public var scannedNodes:Int?
    public var hasExternalLinks = false
    public static func sizeLabel(_ allocated:UInt64,complete:Bool)->String {complete ? bytes(allocated) : allocated==0 ? "Not measured" : "At least "+bytes(allocated)}
    public var label: String { Self.sizeLabel(allocated,complete:complete) }
}
public struct ScanLimits: Sendable {
    public var nodes: Int; public var seconds: TimeInterval
    public init(nodes: Int = 100_000, seconds: TimeInterval = 25) { self.nodes = nodes; self.seconds = seconds }
}
public enum FileScanner {
    // No symlinks followed; physical allocation counted once for each device/inode pair.
    public static func measure(_ url: URL, limits: ScanLimits = ScanLimits(), exclusions: [String] = [], returnPartialOnCancellation:Bool=false, diskAccounting:Bool=false, allocation:@Sendable (Identity,UInt64,UInt64)->Void={_,_,_ in}, progress: @Sendable (Int) -> Void = { _ in }) throws -> Measurement {
        var result = Measurement(); var seen = Set<String>(); var linkCounts: [String: Int] = [:]; var linkExpected: [String: Int] = [:]
        let root = physicalURL(url); let exclusions = exclusions.map { physicalURL(URL(fileURLWithPath:$0)).path }
        var visited=0
        var stack = [root]; let deadline = ProcessInfo.processInfo.systemUptime+limits.seconds
        while let next = stack.popLast() {
            if Task.isCancelled && returnPartialOnCancellation {result.complete=false;result.issues.append("Scan stopped; this is a partial measurement.");break}
            try Task.checkCancellation()
            if visited >= limits.nodes || ProcessInfo.processInfo.systemUptime > deadline { result.complete = false; result.issues.append("Scan budget reached. Refresh a smaller folder."); break }
            if exclusions.contains(where: { within(next.path, $0) }) { result.complete = false; result.issues.append("Excluded: \(next.lastPathComponent)"); continue }
            do {
                let id = try Identity.read(next); visited += 1; if !diskAccounting || next==root {result.manifest[next.path] = id}
                if diskAccounting && (id.isDirectory || id.isSymlink) {
                    var metadata=stat();guard lstat(next.path,&metadata)==0,metadata.st_dev==id.device,metadata.st_ino==id.inode else {throw BonsaiError.changed("Item changed during measurement")}
                    let key="\(id.device):\(id.inode)"
                    if seen.insert(key).inserted {let allocated=UInt64(max(0,metadata.st_blocks))*512;result.allocated += allocated;allocation(id,allocated,0)}
                }
                if id.isSymlink {
                    if !diskAccounting && (next == root || !within(physicalURL(next.resolvingSymlinksInPath()).path, root.path)) { result.complete = false; result.issues.append("External symbolic link omitted: \(next.lastPathComponent)") }
                    // Contained bundle links are recorded but never traversed.
                    continue
                }
                if id.isDirectory {
                    let contents=try DirectoryListing.read(next,limit:max(0,limits.nodes-visited-stack.count),expected:id,deadlineUptime:deadline)
                    if !contents.complete {result.complete=false;result.issues.append("Directory listing budget reached. Choose a smaller folder.")}
                    stack.append(contentsOf:contents.urls.map(physicalURL).sorted {$0.path>$1.path})
                } else {
                    let key = "\(id.device):\(id.inode)"; linkCounts[key, default: 0] += 1; linkExpected[key] = Int(id.links)
                    if seen.insert(key).inserted {
                        var s = stat(); guard lstat(next.path, &s) == 0, s.st_dev==id.device, s.st_ino==id.inode, s.st_uid==id.owner, s.st_mode==id.mode, s.st_size==id.size, Int64(s.st_mtimespec.tv_sec)==id.modified, Int64(s.st_mtimespec.tv_nsec)==id.nanos else { throw BonsaiError.changed("File changed while being measured") }
                        let logical=UInt64(max(0,s.st_size)),allocated=UInt64(max(0,s.st_blocks))*512
                        result.logical += logical;result.allocated += allocated;result.files += 1;allocation(id,allocated,logical)
                    }
                }
                if visited % 256 == 0 { progress(visited) }
            } catch is CancellationError {
                if !returnPartialOnCancellation {throw CancellationError()}
                result.complete=false;result.issues.append("Scan stopped; this is a partial measurement.");break
            } catch {
                result.complete=false
                if FileAccess.isPermission(error), (result.accessDeniedPaths?.count ?? 0)<30 {if result.accessDeniedPaths==nil {result.accessDeniedPaths=[]};result.accessDeniedPaths?.append(next.path)}
                if result.issues.count<30 {result.issues.append("\(next.lastPathComponent): \(error.localizedDescription)")}
            }
        }
        result.hasExternalLinks = linkExpected.contains { key, expected in expected > (linkCounts[key] ?? 0) }
        result.scannedNodes=visited
        progress(visited); return result
    }
}
public enum UserCacheLocation {
    public static var url:URL? {
        let count=confstr(_CS_DARWIN_USER_CACHE_DIR,nil,0)
        guard count>1,count<16_384 else { return nil }
        var buffer=[CChar](repeating:0,count:count)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR,&buffer,count)>0 else { return nil }
        return String(validatingCString:buffer).map { physicalURL(URL(fileURLWithPath:$0)) }
    }
}
public struct PathPolicy: Sendable {
    public let roots: [URL]; public let protected: [URL]; public let uid: UInt32
    public init(roots: [URL], protected: [URL] = [], uid: UInt32 = getuid()) {
        self.roots = roots.map(physicalURL); self.protected = protected.map(physicalURL); self.uid = uid
    }
    public static var standard: PathPolicy {
        let h = FileManager.default.homeDirectoryForCurrentUser
        let selfApp = Bundle.main.bundleURL.pathExtension == "app" ? [Bundle.main.bundleURL] : []
        return PathPolicy(roots: [h, URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSTemporaryDirectory())] + (UserCacheLocation.url.map { [$0] } ?? []), protected: [h.appendingPathComponent(".ssh"),h.appendingPathComponent(".gnupg"),h.appendingPathComponent(".aws"),h.appendingPathComponent(".azure"),h.appendingPathComponent(".kube"),h.appendingPathComponent(".config"),h.appendingPathComponent(".netrc"),h.appendingPathComponent(".npmrc"),h.appendingPathComponent(".git-credentials"),h.appendingPathComponent(".codex/auth.json"),h.appendingPathComponent(".Trash"),h.appendingPathComponent("Library/Keychains"),h.appendingPathComponent("Library/Mail"),h.appendingPathComponent("Library/Messages"),h.appendingPathComponent("Library/CloudStorage"),h.appendingPathComponent("Library/Containers"),h.appendingPathComponent("Library/Group Containers")] + AppIdentity.protectedFolderNames.map {h.appendingPathComponent("Library/Application Support/"+$0)} + selfApp)
    }
    public func validate(_ url: URL, expected: Identity? = nil) throws {
        let url = physicalURL(url); let path = url.path
        guard !path.split(separator:"/",omittingEmptySubsequences:false).contains(where: { $0 == "." || $0 == ".." }), roots.contains(where: { within(path, $0.path) && path != $0.path }) else { throw BonsaiError.refused("Outside permitted locations or a location root.") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let broad = [home + "/Library",home + "/Library/Application Support",home + "/Library/Caches",home + "/Library/Preferences",home + "/Library/Developer",home + "/Applications"]
        guard !broad.contains(path), !protected.contains(where: { within(path,$0.path) || within($0.path,path) }) else { throw BonsaiError.refused("Protected or broad location. Choose a specific cache or file.") }
        var ancestor = url
        while ancestor.path != "/" {
            let id = try Identity.read(ancestor)
            guard !id.isSymlink else { throw BonsaiError.refused("A path component is a symbolic link.") }
            ancestor.deleteLastPathComponent()
        }
        let id = try Identity.read(url)
        guard id.owner == uid else { throw BonsaiError.refused("This item is owned by another user. Manage it in Finder with appropriate authorization.") }
        if let expected, id != expected { throw BonsaiError.changed("Item changed since review. Scan again.") }
    }
}
public struct ReviewItem: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL; public let title: String; public let category: String; public let explanation: String
    public let risk: String; public let confidence: String; public let runningIDs: [String]
    public let measurement: Measurement; public let parentIdentity: Identity; public let absentBundleID: String?
    public let readOnlyReason: String?
    public init(url: URL, title: String, category: String, explanation: String, risk: String = "Review", confidence: String = "Known path", runningIDs: [String] = [], measurement: Measurement, absentBundleID: String? = nil, readOnlyReason: String? = nil) throws {
        self.url = physicalURL(url); self.title = title; self.category = category; self.explanation = explanation; self.risk = risk; self.confidence = confidence; self.runningIDs = runningIDs; self.measurement = measurement; self.absentBundleID = absentBundleID
        self.parentIdentity = try Identity.read(physicalURL(url).deletingLastPathComponent())
        self.readOnlyReason = readOnlyReason
    }
}
public struct ItemOutcome: Identifiable, Codable, Sendable {
    public let id: UUID; public let title: String; public let path: String; public let status: String; public let detail: String; public let recovery: String?
    public init(title: String, path: String, status: String, detail: String, recovery: String? = nil) { self.id = UUID(); self.title = title; self.path = path; self.status = status; self.detail = detail; self.recovery = recovery }
}
public enum TrashService {
    public static func systemTrash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination.map { $0 as URL }
    }
    public static func perform(_ items: [ReviewItem], policy: PathPolicy = .standard, runningIDs: @Sendable () -> Set<String>, dryRun: Bool = false, permanentCaches:Bool=false, confirmed:Bool=false, cacheHome:URL=FileManager.default.homeDirectoryForCurrentUser, absenceValidator: @Sendable (String) throws -> Void = { try InstalledIdentifiers.verifyAbsent($0) }, mover: @Sendable (URL) throws -> URL? = { try TrashService.systemTrash($0) }, progress: @Sendable (Int,ReviewItem,[ItemOutcome]) async -> Void = {_,_,_ in}) async -> [ItemOutcome] {
        var outcomes: [ItemOutcome] = []
        for (index,item) in items.enumerated() {
            await progress(index,item,outcomes)
            do {
                try Task.checkCancellation()
                guard item.category != "Trash", item.readOnlyReason == nil else { throw BonsaiError.refused(item.readOnlyReason ?? "Trash contents require the separate permanent-deletion review.") }
                let policy = try ContainerCacheScope.policy(for:item,base:policy)
                guard !items.contains(where: { $0.id != item.id && within(item.id, $0.id) }) else { throw BonsaiError.refused("Nested selection. Review only the parent or its children.") }
                guard let expected = item.measurement.manifest[item.id], item.measurement.complete else { throw BonsaiError.refused("Incomplete measurement. Resolve access or scan limits first.") }
                try policy.validate(item.url, expected: expected)
                guard !ApplicationActivity.isRunning(item.runningIDs,among:runningIDs()) else { throw BonsaiError.refused("Related application is running. Quit it and retry.") }
                let current = try FileScanner.measure(item.url)
                guard current.complete, current.manifest == item.measurement.manifest else { throw BonsaiError.changed("Contents changed since review. Scan again.") }
                guard current.manifest.allSatisfy({ path, identity in identity.owner == policy.uid && (!identity.isSymlink || within(physicalURL(URL(fileURLWithPath:path).resolvingSymlinksInPath()).path,item.id)) }) else { throw BonsaiError.refused("Contains another owner's files or symbolic links.") }
                guard try Identity.read(item.url.deletingLastPathComponent()).sameObject(as: item.parentIdentity) else { throw BonsaiError.changed("Parent directory changed. Scan again.") }
                try Task.checkCancellation(); try policy.validate(item.url, expected: expected)
                let running = runningIDs()
                guard !ApplicationActivity.isRunning(item.runningIDs,among:running), !current.manifest.contains(where: { path, identity in
                    identity.isDirectory && URL(fileURLWithPath:path).pathExtension == "app" && Bundle(url:URL(fileURLWithPath:path))?.bundleIdentifier.map(running.contains) == true
                }) else { throw BonsaiError.refused("A related or contained application is now running. Quit it and scan again.") }
                if let identifier=item.absentBundleID { try absenceValidator(identifier) }
                let permanent=permanentCaches && CacheRemovalPolicy.permits(item,home:cacheHome)
                guard !permanent || dryRun || confirmed else {throw BonsaiError.refused("Permanent cache removal requires explicit confirmation.")}
                if dryRun { outcomes.append(ItemOutcome(title: item.title, path: item.id, status: "Preview", detail: permanent ? "Permanent cache-removal preview validated. No files changed.":"Validated. No files changed.")); continue }
                if permanent {
                    do {
                        try FileManager.default.removeItem(at:item.url)
                        do {_=try Identity.read(item.url);throw BonsaiError.unavailable("An item remains at the original cache path. Refresh to verify.")} catch {guard FileAccess.status(error) == .missing else {throw error}}
                    } catch {outcomes.append(ItemOutcome(title:item.title,path:item.id,status:"Partial failure",detail:"Cache deletion began; some contents may remain or have been replaced. Refresh before retrying. "+error.localizedDescription));continue}
                    outcomes.append(ItemOutcome(title:item.title,path:item.id,status:"Deleted",detail:item.measurement.label+" of generated cache permanently deleted. No Trash recovery is available. Hardlinks and APFS snapshots may retain storage."));continue
                }
                let moved = try mover(item.url)
                outcomes.append(ItemOutcome(title: item.title, path: item.id, status: "Trashed", detail: "\(item.measurement.label) moved to Trash. Space is not freed until Trash is emptied. External hardlinks and APFS clones may retain storage.", recovery: moved?.path))
            } catch {
                outcomes.append(ItemOutcome(title: item.title, path: item.id, status: error is CancellationError ? "Cancelled" : "Skipped", detail: error.localizedDescription))
            }
        }
        return outcomes
    }
}
public struct AuditEntry: Codable, Identifiable, Sendable {
    public let id: UUID; public let date: Date; public let operation: String; public let outcomes: [ItemOutcome]
    public init(operation: String, outcomes: [ItemOutcome]) { id = UUID(); date = Date(); self.operation = operation; self.outcomes = outcomes }
}
public actor AuditStore {
    public let url: URL
    public init(url: URL? = nil) { self.url = url ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(AppIdentity.historyPath) }
    public func read() -> [AuditEntry] { guard let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([AuditEntry].self, from: data) else { return [] }; return entries }
    public func append(_ entry: AuditEntry) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func sanitize(_ s: String) -> String {
            let safe = s.replacingOccurrences(of:home,with:"~").unicodeScalars.filter { $0.value >= 32 || $0.value == 10 }.map(String.init).joined()
            return safe.replacingOccurrences(of:"(https?://)[^\\s/@]+:[^\\s/@]+@",with:"$1[redacted]@",options:.regularExpression)
                .replacingOccurrences(of:"(?i)(token|password|authorization|api[_-]?key)\\s*[:=]\\s*[^\\s]+",with:"$1=[redacted]",options:.regularExpression)
        }
        let clean = entry.outcomes.map { ItemOutcome(title: sanitize($0.title),path: sanitize($0.path),status: $0.status,detail: String(sanitize($0.detail).prefix(4096)),recovery: $0.recovery.map(sanitize)) }
        var entries = read(); entries.insert(AuditEntry(operation: entry.operation, outcomes: clean),at: 0); entries = Array(entries.prefix(100))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(entries).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: url.path)
    }
}
