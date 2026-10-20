import Foundation
import Darwin

public enum FileAccessStatus:String,Codable,Sendable {case readable,blocked,missing,unknown}
public struct FileAccessProbe:Identifiable,Sendable {
    public var id:String {url.path}
    public let title:String;public let url:URL;public let status:FileAccessStatus;public let detail:String
}
public struct FileAccessReport:Sendable {
    public let date:Date;public let probes:[FileAccessProbe]
    /// Missing app folders are inconclusive; blocked or unknown probes must not
    /// produce a granted badge. This verifies capability, not the private TCC switch.
    public var accessConfirmed:Bool {
        probes.contains {$0.status == .readable} && probes.allSatisfy {$0.status == .readable || $0.status == .missing}
    }
    public var needsAccess:Bool {probes.contains {$0.status == .blocked}}
    public var summary:String {needsAccess ? "Some protected locations need access" : probes.contains {$0.status == .readable} ? "Checked locations are readable" : "Access could not be established"}
}
public enum FileAccess {
    public static func currentGroups()->[UInt32] {
        var values=[gid_t](repeating:0,count:128)
        let count=getgroups(Int32(values.count),&values)
        return count>0 ? Array(Set(values.prefix(Int(count))+[getgid()])) : [getgid()]
    }
    public static func preferredDeniedURL(_ paths:[String])->URL? {
        let urls=paths.prefix(2_000).map {URL(fileURLWithPath:$0)}
        for route in [FileAccessRoute.fullDiskAccess,.filesAndFolders,.filePermissions,.administrator] {
            if let url=urls.first(where:{FileAccessNeed(url:$0,operation:"Access check").route==route}) {return url}
        }
        return urls.first
    }
    public static func isPermission(_ error:Error)->Bool {
        var current=error as NSError
        for _ in 0..<5 {
            if current.domain==NSPOSIXErrorDomain && [Int(EPERM),Int(EACCES)].contains(current.code) {return true}
            if current.domain==NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(current.code) {return true}
            guard let underlying=current.userInfo[NSUnderlyingErrorKey] as? NSError else {return false};current=underlying
        }
        return false
    }
    public static func deniedURL(_ error:Error,fallback:URL?=nil)->URL? {
        guard isPermission(error) else {return nil}
        var current=error as NSError
        for _ in 0..<5 {
            if let url=current.userInfo[NSURLErrorKey] as? URL,url.isFileURL {return physicalURL(url)}
            if let path=current.userInfo[NSFilePathErrorKey] as? String,path.hasPrefix("/") {return physicalURL(URL(fileURLWithPath:path))}
            guard let next=current.userInfo[NSUnderlyingErrorKey] as? NSError else {break};current=next
        }
        return fallback.map(physicalURL)
    }
    public static func status(_ error:Error)->FileAccessStatus {
        if isPermission(error) {return .blocked}
        let n=error as NSError
        if n.domain==NSPOSIXErrorDomain && n.code==Int(ENOENT) || n.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(n.code) {return .missing}
        return .unknown
    }
    // Public read probes establish capability on these paths, not the TCC switch state.
    // No database contents, arguments or environment are read.
    public static func check(home:URL=FileManager.default.homeDirectoryForCurrentUser,read:@Sendable (URL)throws->Void={url in _=try DirectoryListing.read(url,limit:1)}) -> FileAccessReport {
        let locations=[("Safari data","Library/Safari"),("Mail data","Library/Mail"),("Messages data","Library/Messages")]
        let probes=locations.map {title,path in
            let url=home.appendingPathComponent(path)
            do {try read(url);return FileAccessProbe(title:title,url:url,status:.readable,detail:"Directory metadata readable")}
            catch {return FileAccessProbe(title:title,url:url,status:status(error),detail:error.localizedDescription)}
        }
        return FileAccessReport(date:Date(),probes:probes)
    }
}
public enum FileAccessRoute:String,Sendable {case administrator,fullDiskAccess,filesAndFolders,filePermissions,systemProtection}
public struct FileAccessNeed:Identifiable,Sendable {
    public var id:String {operation+":"+url.path}
    public let operation:String;public let url:URL;public let route:FileAccessRoute
    public init(url:URL,operation:String,inventory:Bool=false,home:URL=FileManager.default.homeDirectoryForCurrentUser,uid:UInt32=getuid(),identity:Identity?=nil,groups:[UInt32]=FileAccess.currentGroups(),privacyReadable:Bool=false) {
        let target=physicalURL(url);self.url=target;self.operation=operation
        let metadata=identity ?? (try? Identity.read(self.url))
        // A different owner's private mode is affirmative evidence of a Unix
        // restriction. Privacy switches cannot grant those missing rights.
        var snapshot=stat()
        let groupKnown=lstat(target.path,&snapshot)==0 && metadata?.device==snapshot.st_dev && metadata?.inode==snapshot.st_ino
        let inGroup=groupKnown && groups.contains(snapshot.st_gid)
        let required:UInt16=metadata?.isDirectory==true ? 0o5:0o4
        if let metadata,metadata.owner != uid,metadata.mode & required != required,(!inGroup || (metadata.mode>>3) & required != required) {
            route=inventory && ["/Applications","/System/Applications"].contains(where:{within(target.path,$0)}) ? .administrator:.filePermissions
        } else if let metadata,metadata.owner==uid,metadata.mode & 0o400 == 0 {
            route = .filePermissions
        } else if ["Desktop","Documents","Downloads"].contains(where:{within(target.path,physicalURL(home.appendingPathComponent($0)).path)}) || within(target.path,"/Volumes") {
            route = .filesAndFolders
        } else {route = privacyReadable ? .systemProtection:.fullDiskAccess}
    }
}
public struct DirectoryContents:Sendable {public let urls:[URL];public let complete:Bool}
public enum DirectoryListing {
    // Bound directory enumeration; compare the opened object with the lstat identity.
    // O_NOFOLLOW prevents a replaced final component from redirecting the scan.
    public static func read(_ url:URL,limit:Int,expected:Identity?=nil,deadlineUptime:TimeInterval?=nil) throws -> DirectoryContents {
        let fd=open(url.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        var metadata=stat()
        if fstat(fd,&metadata) != 0 {let code=errno;close(fd);throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
        if let expected,metadata.st_dev != expected.device || metadata.st_ino != expected.inode || metadata.st_uid != expected.owner || metadata.st_mode != expected.mode {close(fd);throw BonsaiError.changed("Directory changed while it was being opened.")}
        guard let directory=fdopendir(fd) else {let code=errno;close(fd);throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
        defer {closedir(directory)}
        var urls:[URL]=[];var complete=true;var visited=0
        while true {
            try Task.checkCancellation()
            if let deadlineUptime,ProcessInfo.processInfo.systemUptime>deadlineUptime {complete=false;break}
            errno=0
            guard let entry=readdir(directory) else {if errno != 0 {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};break}
            var name=entry.pointee.d_name
            let string=withUnsafePointer(to:&name) {$0.withMemoryRebound(to:CChar.self,capacity:Int(MAXPATHLEN)) {String(validatingCString:$0)}}
            if string=="." || string==".." {continue}
            visited += 1
            guard visited<=max(0,limit) else {complete=false;break}
            guard let string else {complete=false;continue}
            urls.append(url.appendingPathComponent(string))
        }
        return DirectoryContents(urls:urls,complete:complete)
    }
}
