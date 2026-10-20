import Foundation
import CryptoKit
import Security
import CBonsai

public enum StoreUpdates {
    public static func bundleID(_ item:SoftwareUpdate)->String? {
        guard item.source=="App Store",item.id.hasPrefix("store:") else {return nil}
        let value=String(item.id.dropFirst(6))
        return value.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{1,254}\\z",options:.regularExpression) != nil ? value : nil
    }
    public static func install(_ item:SoftwareUpdate,consent:Bool,redownload:Bool=false,progress:@escaping SoftwareUpdateProgressHandler={_ in}) async -> ItemOutcome {
        do {
            guard consent,let id=bundleID(item),let app=item.applicationURL else {throw BonsaiError.refused("A verified installed App Store app is required.")}
            let current=Bundle(url:app)
            guard current?.bundleIdentifier==id,FileManager.default.fileExists(atPath:app.appendingPathComponent("Contents/_MASReceipt/receipt").path) else {throw BonsaiError.changed("The App Store application changed. Refresh and retry.")}
            let initialBuild=current?.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BonsaiStoreUpdate")
            let mas=helper.deletingLastPathComponent().appendingPathComponent("mas")
            guard !(try Identity.read(helper)).isSymlink,!(try Identity.read(mas)).isSymlink,SHA256.hash(data:try Data(contentsOf:mas)).map({String(format:"%02x",$0)}).joined()=="1a9ec80879b029b67fe3de485203722cfdbee8589fdd70d3bf3c3df59c9f32c9" else {throw BonsaiError.refused("App Store helper integrity failed. Reinstall Bonsai.")}
            try Task.checkCancellation()
            progress(SoftwareUpdateProgress(.installing))
            let worker=Task.detached(priority:.utility) {()->(Int32,String) in
                var output:UnsafeMutablePointer<CChar>?
                let status=helper.path.withCString {path in id.withCString {identifier in
                    redownload ? app.path.withCString {application in bonsai_redownload_store(path,identifier,application,&output)} : bonsai_update_store(path,identifier,&output)
                }}
                defer {if let output {bonsai_free_inventory(output)}}
                return (status,output.map {String(cString:$0)} ?? "")
            }
            let (status,output)=await worker.value
            let authorizationDetail=status == 0 ? "" : status>=50000 ? "\nUpdate helper exited with status \(status-50000)." : "\nApp Store helper status \(status): \(SecCopyErrorMessageString(status,nil) as String? ?? "Authorization or helper execution failed.")"
            progress(SoftwareUpdateProgress(.checking))
            let data=try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
            let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
            let version=info?["CFBundleShortVersionString"] as? String ?? ""
            let build=info?["CFBundleVersion"] as? String ?? ""
            let updated=info?["CFBundleIdentifier"] as? String==id && (VersionOrder.newer(version,than:item.installed) || (version==item.installed && VersionOrder.newer(build,than:initialBuild)))
            return ItemOutcome(title:item.name,path:item.id,status:updated ? "Updated" : status == -60006 ? "Cancelled" : "Needs attention",detail:updated ? "Installed App Store version verified: "+version : "The installed version has not changed. macOS approval and an App Store account may be required. An Apple download already started can continue in the background.\n"+output+authorizationDetail)
        } catch {return ItemOutcome(title:item.name,path:item.id,status:error is CancellationError ? "Cancelled" : "Failed",detail:error.localizedDescription)}
    }
}
