import Foundation
import Darwin
import CBonsai

private struct DiskInode:Hashable {let device:Int32;let inode:UInt64}
private final class DiskWalkState {
    let root:URL;let collectChildren:Bool;var rootAllocated:UInt64=0;let allocation:@Sendable (Identity,UInt64,UInt64)->Void;let progress:@Sendable (Int)->Void
    var children:[String:Measurement]=[:];var childLinks:[String:Set<DiskInode>]=[:]
    let largestLimit:Int;var largest:[DiskEntry]=[]
    var result=Measurement();var nodes=0;var hardlinks:[DiskInode:(count:Int,expected:Int)]=[:]
    init(root:URL,collectChildren:Bool,largestLimit:Int=0,allocation:@escaping @Sendable (Identity,UInt64,UInt64)->Void,progress:@escaping @Sendable (Int)->Void) {self.root=root;self.collectChildren=collectChildren;self.largestLimit=largestLimit;self.allocation=allocation;self.progress=progress}
    func visit(path:UnsafePointer<CChar>,node:UnsafePointer<bonsai_disk_node>?,error:Int32)->Int32 {
        if Task.isCancelled {return 1}
        nodes+=1
        if let n=node?.pointee {
            let identity=Identity(device:n.device,inode:n.inode,owner:n.owner,mode:n.mode,size:n.size,modified:n.modified,nanos:n.nanos,links:n.links)
            if nodes==1 {result.manifest[root.path]=identity;rootAllocated=n.allocated}
            let key=DiskInode(device:n.device,inode:n.inode)
            let linked = !identity.isDirectory && identity.links>1
            if collectChildren && nodes>1 {
                let full=String(cString:path)
                let relative=full.dropFirst(root.path.count+(root.path=="/" ? 0:1))
                if let name=relative.split(separator:"/",maxSplits:1).first {
                    let child=root.appendingPathComponent(String(name)).path
                    if children[child]==nil {children[child]=Measurement()}
                    if full==child {children[child]?.manifest[child]=identity}
                    if !linked || childLinks[child,default:[]].insert(key).inserted {
                        children[child]?.allocated+=n.allocated
                        children[child]?.logical+=identity.isDirectory || identity.isSymlink ? 0:UInt64(max(0,identity.size))
                        if !identity.isDirectory && !identity.isSymlink {children[child]?.files+=1}
                    }
                }
            }
            if largestLimit>0,identity.mode & 0o170000 == 0o100000,n.allocated>0,
               largest.count<largestLimit || n.allocated>largest.last!.measurement.allocated {
                let url=URL(fileURLWithPath:String(cString:path))
                var measured=Measurement();measured.allocated=n.allocated;measured.logical=UInt64(max(0,identity.size));measured.files=1;measured.manifest[url.path]=identity
                largest.append(DiskEntry(url:url,directory:false,measurement:measured))
                largest.sort {$0.measurement.allocated == $1.measurement.allocated ? $0.id<$1.id : $0.measurement.allocated>$1.measurement.allocated}
                if largest.count>largestLimit {largest.removeLast()}
            }
            let previous=linked ? hardlinks[key]?.count ?? 0:0
            if linked {hardlinks[key]=(previous+1,Int(identity.links))}
            if previous==0 {
                let logical = identity.isDirectory || identity.isSymlink ? 0:UInt64(max(0,identity.size))
                result.logical+=logical;result.allocated+=n.allocated
                if !identity.isDirectory && !identity.isSymlink {result.files+=1}
                allocation(identity,n.allocated,logical)
            }
        }
        if error != 0 {
            result.complete=false
            if result.issues.count<30 {let name=URL(fileURLWithPath:String(cString:path)).lastPathComponent;result.issues.append(name+": "+NSError(domain:NSPOSIXErrorDomain,code:Int(error)).localizedDescription)}
            if [EPERM,EACCES].contains(error),(result.accessDeniedPaths?.count ?? 0)<30 {if result.accessDeniedPaths==nil {result.accessDeniedPaths=[]};result.accessDeniedPaths?.append(String(cString:path))}
        }
        if nodes%256==0 {progress(nodes)}
        return 0
    }
}
/// Read-only, constant-depth native traversal. Removal still uses the separate
/// full manifest scanner and identity revalidation; this is never authorization.
public enum DiskTreeScanner {
    public static func measure(_ url:URL,limits:ScanLimits,allocation:@escaping @Sendable (Identity,UInt64,UInt64)->Void={_,_,_ in},progress:@escaping @Sendable (Int)->Void={_ in},collectChildren:Bool=false,children:([DiskEntry],UInt64)->Void={_,_ in},largestLimit:Int=0,largestFiles:([DiskEntry])->Void={_ in}) throws -> Measurement {
        try Task.checkCancellation()
        let root=physicalURL(url),state=DiskWalkState(root:root,collectChildren:collectChildren,largestLimit:min(200,max(0,largestLimit)),allocation:allocation,progress:progress)
        let context=Unmanaged.passUnretained(state).toOpaque()
        let status=bonsai_disk_walk(root.path,UInt64(max(0,limits.nodes)),max(0,limits.seconds),context) {context,path,node,error in
            guard let context,let path else {return 1}
            return Unmanaged<DiskWalkState>.fromOpaque(context).takeUnretainedValue().visit(path:path,node:node,error:error)
        }
        if status<0 {throw NSError(domain:NSPOSIXErrorDomain,code:Int(-status))}
        if status != 0 {state.result.complete=false;state.result.issues.append(status==1 ? "Scan stopped; this is a partial measurement.":"Scan budget reached. Refresh a smaller folder.")}
        state.result.scannedNodes=state.nodes;state.result.hasExternalLinks=state.hardlinks.values.contains {$0.expected>$0.count}
        if collectChildren && state.result.complete && state.children.count<=10_000 {
            children(state.children.compactMap {path,measurement in
                guard let identity=measurement.manifest[path] else {return nil}
                return DiskEntry(url:URL(fileURLWithPath:path),directory:identity.isDirectory,measurement:measurement)
            },state.result.allocated>=state.rootAllocated ? state.result.allocated-state.rootAllocated:0)
        }
        largestFiles(state.largest)
        progress(state.nodes);return state.result
    }
}

public struct LargestDiskFilesResult:Sendable {
    public let entries:[DiskEntry]
    public let complete:Bool
}
public enum LargestDiskFiles {
    /// Bounded metadata-only search, storing at most 100 file identities per root.
    public static func scan(roots:[URL],limit:Int=100,limits:ScanLimits=ScanLimits(nodes:300_000,seconds:20)) throws -> LargestDiskFilesResult {
        let cap=min(200,max(1,limit)),start=ProcessInfo.processInfo.systemUptime
        var files:[DiskEntry]=[],nodes=0,complete=true
        for root in roots {
            try Task.checkCancellation()
            let seconds=limits.seconds-(ProcessInfo.processInfo.systemUptime-start)
            guard seconds>0,nodes<limits.nodes else {complete=false;break}
            do {
                let measured=try DiskTreeScanner.measure(root,limits:ScanLimits(nodes:limits.nodes-nodes,seconds:seconds),largestLimit:cap,largestFiles:{files += $0})
                nodes += measured.scannedNodes ?? 0;complete = complete && measured.complete
            } catch is CancellationError {throw CancellationError()}
            catch {complete=false}
        }
        try Task.checkCancellation()
        var paths=Set<String>()
        let entries=files.sorted {$0.measurement.allocated == $1.measurement.allocated ? $0.id<$1.id : $0.measurement.allocated>$1.measurement.allocated}.filter {paths.insert($0.id).inserted}
        return LargestDiskFilesResult(entries:Array(entries.prefix(cap)),complete:complete)
    }
}
