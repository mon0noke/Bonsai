import Foundation
import Darwin
import AppKit
import Security
import CryptoKit
import CBonsai

private final class ArtifactSession:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    let progress:SoftwareUpdateProgressHandler
    private var lastReport:TimeInterval=0
    init(progress:@escaping SoftwareUpdateProgressHandler) {self.progress=progress}

    private let completionLock=NSLock()
    private var completedResult:Result<(URL,URLResponse),Error>?
    private var continuation:CheckedContinuation<(URL,URLResponse),Error>?
    private var destination:URL?
    private var completedFile:URL?
    private var fileError:Error?
    func download(_ url:URL,session:URLSession,to destination:URL) async throws -> (URL,URLResponse) {
        self.destination=destination
        let task=session.downloadTask(with:url)
        return try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation {continuation in
                completionLock.lock()
                if let completedResult {completionLock.unlock();continuation.resume(with:completedResult)}
                else {self.continuation=continuation;completionLock.unlock()}
                task.resume()
            }
        },onCancel:{task.cancel()})
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        do {
            guard let destination else {throw BonsaiError.unavailable("Download destination unavailable.")}
            try FileManager.default.moveItem(at:location,to:destination)
            completedFile=destination;progress(SoftwareUpdateProgress(.downloading,fraction:1))
        } catch {fileError=error}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        let result:Result<(URL,URLResponse),Error>
        if let error=fileError ?? error {result = .failure(error)}
        else if let completedFile,let response=task.response {result = .success((completedFile,response))}
        else {result = .failure(BonsaiError.unavailable("Download did not complete."))}
        completionLock.lock();completedResult=result
        let continuation=self.continuation;self.continuation=nil;completionLock.unlock()
        continuation?.resume(with:result)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>1_073_741_824 || totalBytesExpectedToWrite>1_073_741_824 {downloadTask.cancel();return}
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastReport>=0.1 || totalBytesWritten==totalBytesExpectedToWrite {
            lastReport=now;progress(.download(received:totalBytesWritten,total:totalBytesExpectedToWrite))
        }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {completionHandler(request.url.map(PublicMetadataHTTP.valid)==true ? request : nil)}
}
public enum DirectUpdates {
    public static func extract(_ archive:URL,to destination:URL) throws {
        guard try Identity.read(destination).isDirectory else {throw BonsaiError.refused("Missing extraction directory.")}
        let status=archive.path.withCString {a in destination.path.withCString {d in bonsai_extract_update(a,d)}}
        guard status==0 else {throw BonsaiError.refused("Update archive is invalid, too large, or contains unsafe paths or links.")}
    }
    /// Pinned identities checked against fresh, checksum-verified official
    /// releases. These repair an invalid old copy without trusting its signature.
    public static func recoveryTeam(_ identifier:String)->String? {
        switch identifier {
        case "ch.protonvpn.mac":return "J6S6Q257EK" // vpn.protondownload.com
        case "com.todesktop.241012ess7yxs0e":return "6FXBT88W8J" // download.todesktop.com/241130tqe9q3y
        default:return nil
        }
    }
    public static func verifyPublisher(installed:URL,candidate:URL) throws {
        var original:SecStaticCode?,replacement:SecStaticCode?,requirement:SecRequirement?
        let flags=SecCSFlags(rawValue:kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        if let identifier=Bundle(url:installed)?.bundleIdentifier,let team=recoveryTeam(identifier) {
            let text="anchor apple generic and identifier \""+identifier+"\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \""+team+"\""
            guard SecRequirementCreateWithString(text as CFString,[],&requirement)==errSecSuccess else {throw BonsaiError.refused("Publisher identity unavailable.")}
        } else {
            guard SecStaticCodeCreateWithPath(installed as CFURL,[],&original)==errSecSuccess,let original,
                  SecStaticCodeCheckValidity(original,flags,nil)==errSecSuccess,
                  SecCodeCopyDesignatedRequirement(original,[],&requirement)==errSecSuccess else {throw BonsaiError.refused("Installed publisher signature could not be verified.")}
        }
        guard let requirement,SecStaticCodeCreateWithPath(candidate as CFURL,[],&replacement)==errSecSuccess,let replacement,
              SecStaticCodeCheckValidity(replacement,flags,requirement)==errSecSuccess else {throw BonsaiError.refused("Publisher signature does not match the installed app. Nothing was replaced.")}
    }
    public static func verifyArchive(_ archive:URL,item:SoftwareUpdate,publicKey:String?) throws {
        try Task.checkCancellation()
        let identity=try Identity.read(archive)
        guard !identity.isSymlink,identity.mode & UInt16(S_IFMT)==UInt16(S_IFREG),identity.size<=1_073_741_824 else {throw BonsaiError.refused("Unsupported update archive.")}
        if let length=item.downloadBytes,identity.size != length {throw BonsaiError.refused("Publisher archive size did not match. Nothing was replaced.")}
        if item.source=="Electron" {
            guard let expected=item.downloadSHA512 else {throw BonsaiError.refused("Missing publisher checksum.")}
            let handle=try FileHandle(forReadingFrom:archive);defer {try? handle.close()};var digest=SHA512()
            while let chunk=try handle.read(upToCount:65536),!chunk.isEmpty {try Task.checkCancellation();digest.update(data:chunk)}
            guard Data(digest.finalize()).base64EncodedString()==expected else {throw BonsaiError.refused("Publisher download checksum did not match. Nothing was replaced.")}
        } else if item.usesSparkle {
            // Legacy feeds without an Ed25519 key still require the original
            // publisher's strict nested code-signing requirement before any swap.
            if let publicKey {
                guard let key=Data(base64Encoded:publicKey),key.count==32,let signature=item.downloadSignature.flatMap({Data(base64Encoded:$0)}),signature.count==64 else {throw BonsaiError.refused("Publisher archive signature is missing or invalid. Nothing was replaced.")}
                try Task.checkCancellation()
                let verifier=try Curve25519.Signing.PublicKey(rawRepresentation:key)
                guard verifier.isValidSignature(signature,for:try Data(contentsOf:archive,options:.mappedIfSafe)) else {throw BonsaiError.refused("Publisher archive signature did not match. Nothing was replaced.")}
            }
        } else if ["Website","Homebrew catalog","Homebrew package"].contains(item.source) {
            guard let expected=item.downloadSHA256,expected.range(of:"^[0-9a-fA-F]{64}$",options:.regularExpression) != nil else {throw BonsaiError.refused("Missing catalog checksum.")}
            let handle=try FileHandle(forReadingFrom:archive);defer {try? handle.close()};var digest=SHA256()
            while let chunk=try handle.read(upToCount:65536),!chunk.isEmpty {try Task.checkCancellation();digest.update(data:chunk)}
            guard digest.finalize().map({String(format:"%02x",$0)}).joined()==expected.lowercased() else {throw BonsaiError.refused("Catalog download checksum did not match. Nothing was replaced.")}
        } else {throw BonsaiError.refused("Unsupported direct update source.")}
        guard try Identity.read(archive)==identity else {throw BonsaiError.changed("Update archive changed during verification.")}
    }
    public static func releaseMatches(item:SoftwareUpdate,initialVersion:String,initialBuild:String,version:String,build:String)->Bool {
        guard initialVersion==item.installed else {return false}
        if item.usesSparkle {
            if let expected=item.availableBuild,!expected.isEmpty,build != expected {return false}
            if !item.available.hasPrefix("Build "),version != item.available {return false}
            return VersionOrder.newer(version,than:initialVersion) || (version==initialVersion && VersionOrder.newer(build,than:initialBuild))
        }
        if ["Website","Homebrew catalog"].contains(item.source) {
            let parts=item.available.split(separator:",").map(String.init)
            guard version==parts.first else {return false}
            if parts.count>1,build != parts[1] {return false}
            return VersionOrder.newer(version,than:initialVersion) || (version==initialVersion && VersionOrder.newer(build,than:initialBuild))
        }
        return VersionOrder.newer(version,than:initialVersion) && !VersionOrder.newer(item.available,than:version)
    }
    public static func preparePackage(_ item:SoftwareUpdate,progress:@escaping SoftwareUpdateProgressHandler={_ in}) async throws -> URL {
        guard item.canPrepareInstaller,let url=item.downloadURL else {throw BonsaiError.refused("A verified publisher package is required.")}
        let root=physicalURL(FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-installer-"+UUID().uuidString))
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.timeoutIntervalForResource=600
            let delegate=ArtifactSession(progress:progress)
            let downloadSession=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
            defer {downloadSession.invalidateAndCancel()}
            progress(SoftwareUpdateProgress(.downloading))
            let package=root.appendingPathComponent("Installer.pkg")
            let (_,response)=try await delegate.download(url,session:downloadSession,to:package)
            guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),response.url.map(PublicMetadataHTTP.valid)==true else {throw BonsaiError.unavailable("Installer download failed.")}
            progress(SoftwareUpdateProgress(.verifying))
            try await verifyPackage(package,item:item)
            return package
        } catch {try? FileManager.default.removeItem(at:root);throw error}
    }
    public static func verifyPackage(_ package:URL,item:SoftwareUpdate) async throws {
        try verifyArchive(package,item:item,publicKey:nil)
        let checked=try await CommandRunner.checkUpdatePackage(package)
        guard checked.succeeded,checked.output.contains("Developer ID Installer:"),checked.output.contains("Apple Root CA") else {throw BonsaiError.refused("Publisher installer signature could not be verified.")}
    }
    public static func install(_ item:SoftwareUpdate,consent:Bool,progress:@escaping SoftwareUpdateProgressHandler={_ in}) async -> ItemOutcome {
        var workspace:URL?,staged:URL?
        defer {if let workspace {try? FileManager.default.removeItem(at:workspace)};if let staged {try? FileManager.default.removeItem(at:staged)}}
        do {
            guard consent,let url=item.downloadURL,PublicMetadataHTTP.valid(url),item.usesDirectArchive,let app=item.applicationURL,let bundle=Bundle(url:app),let identifier=bundle.bundleIdentifier else {throw BonsaiError.refused("This publisher does not provide a supported direct-update archive.")}
            guard app.standardizedFileURL==app,app.pathExtension=="app",identifier != Bundle.main.bundleIdentifier else {throw BonsaiError.refused("Unsupported application path.")}
            let identity=try Identity.read(app),parent=try Identity.read(app.deletingLastPathComponent())
            let initialData=try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
            guard initialData.count<=1_048_576,let initial=try PropertyListSerialization.propertyList(from:initialData,format:nil) as? [String:Any],let initialVersion=initial["CFBundleShortVersionString"] as? String,initialVersion==item.installed else {throw BonsaiError.changed("The installed version changed. Refresh updates before retrying.")}
            let initialBuild=initial["CFBundleVersion"] as? String ?? ""
            if recoveryTeam(identifier)==nil {try verifyPublisher(installed:app,candidate:app)}
            let policy=PathPolicy(roots:[app.deletingLastPathComponent()]);try policy.validate(app,expected:identity)
            guard !NSWorkspace.shared.runningApplications.contains(where:{$0.bundleIdentifier==identifier}) else {throw BonsaiError.refused("Quit this app before installing its update.")}
            let root=physicalURL(FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-update-"+UUID().uuidString));workspace=root
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.timeoutIntervalForResource=600;config.timeoutIntervalForRequest=30
            let delegate=ArtifactSession(progress:progress)
            let session=URLSession(configuration:config,delegate:delegate,delegateQueue:nil);defer {session.invalidateAndCancel()}
            progress(SoftwareUpdateProgress(.downloading))
            let (temporary,response)=try await delegate.download(url,session:session,to:root.appendingPathComponent("download"))
            guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),response.url.map(PublicMetadataHTTP.valid)==true,(try Identity.read(temporary)).size<=1_073_741_824 else {throw BonsaiError.unavailable("Publisher download failed or exceeded the size limit.")}
            let archive=root.appendingPathComponent("update."+url.pathExtension.lowercased());try FileManager.default.moveItem(at:temporary,to:archive)
            progress(SoftwareUpdateProgress(.verifying))
            try verifyArchive(archive,item:item,publicKey:initial["SUPublicEDKey"] as? String)
            let extracted=root.appendingPathComponent("extracted");try FileManager.default.createDirectory(at:extracted,withIntermediateDirectories:false)
            try Task.checkCancellation()
            progress(SoftwareUpdateProgress(.extracting))
            if archive.pathExtension=="dmg" {try await DiskImageUpdates.extract(archive,to:extracted,bundleID:identifier)}
            else {try extract(archive,to:extracted)}
            try Task.checkCancellation()
            var queue=[(extracted,0)],matches:[URL]=[]
            while let (folder,depth)=queue.popLast() {
                for entry in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
                    let id=try Identity.read(entry);guard id.isDirectory,!id.isSymlink else {continue}
                    if entry.pathExtension=="app" {if Bundle(url:entry)?.bundleIdentifier==identifier {matches.append(entry)}}
                    else if depth<3 {queue.append((entry,depth+1))}
                }
            }
            guard matches.count==1,let candidate=matches.first,let info=Bundle(url:candidate)?.infoDictionary,let version=info["CFBundleShortVersionString"] as? String,releaseMatches(item:item,initialVersion:initialVersion,initialBuild:initialBuild,version:version,build:info["CFBundleVersion"] as? String ?? "") else {throw BonsaiError.refused("Downloaded app identity or version does not match this update.")}
            try verifyPublisher(installed:app,candidate:candidate)
            progress(SoftwareUpdateProgress(.installing))
            let stage=app.deletingLastPathComponent().appendingPathComponent(".Bonsai-update-"+UUID().uuidString+".app");staged=stage
            try FileManager.default.copyItem(at:candidate,to:stage)
            try verifyPublisher(installed:app,candidate:stage)
            try Task.checkCancellation();try policy.validate(app,expected:identity)
            guard try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))==initialData,try Identity.read(app.deletingLastPathComponent()).sameObject(as:parent),!NSWorkspace.shared.runningApplications.contains(where:{$0.bundleIdentifier==identifier}) else {throw BonsaiError.changed("The app started or its parent changed. Retry after quitting it.")}
            // Atomic same-directory swap retains the old application for recovery.
            guard renamex_np(stage.path,app.path,UInt32(RENAME_SWAP))==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            do {
                progress(SoftwareUpdateProgress(.checking))
                try verifyPublisher(installed:stage,candidate:app)
                let installedData=try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
                let installedInfo=try PropertyListSerialization.propertyList(from:installedData,format:nil) as? [String:Any]
                guard installedInfo?["CFBundleShortVersionString"] as? String==version,installedInfo?["CFBundleVersion"] as? String==info["CFBundleVersion"] as? String else {throw BonsaiError.changed("Installed version verification failed.")}
            } catch {
                if renamex_np(stage.path,app.path,UInt32(RENAME_SWAP)) != 0 {staged=nil;throw BonsaiError.changed("Verification failed; previous app is preserved at "+stage.path)}
                throw error
            }
            // Never remove the old bundle if Trash recovery itself fails.
            staged=nil
            let recovery=(try? TrashService.systemTrash(stage)) ?? stage
            return ItemOutcome(title:item.name,path:item.id,status:"Updated",detail:"Installed version "+version+" verified against the original publisher signature. Previous app kept for recovery.",recovery:recovery.path)
        } catch {return ItemOutcome(title:item.name,path:item.id,status:Task.isCancelled || error is CancellationError ? "Cancelled" : "Failed",detail:error.localizedDescription)}
    }
}
