import AppKit
import BonsaiCore
#if BONSAI_DIRECT_SPARKLE
import Sparkle

/// A separate verified updater targets the publisher's bundle, not Bonsai.
/// Publisher keys and feed configuration stay in their original signed bundle.
@MainActor final class SparkleUpdates:NSObject,SPUUpdaterDelegate {
    static let shared=SparkleUpdates()
    private var updater:SPUUpdater?
    private var active=false
    private var finished=false
    private var failure:Error?
    func updaterShouldPromptForPermissionToCheck(forUpdates updater:SPUUpdater)->Bool {false}
    func updater(_ updater:SPUUpdater,mayPerform updateCheck:SPUUpdateCheck) throws {
        guard active,updateCheck == .updates else {throw BonsaiError.refused("Bonsai only starts updates you request.")}
    }
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {failure=error;finished=true;active=false}
    func run(_ item:SoftwareUpdate,progress:SoftwareUpdateProgressHandler={_ in}) async -> ItemOutcome {
        guard !active,let url=item.applicationURL,let bundle=Bundle(url:url),bundle.bundleIdentifier != Bundle.main.bundleIdentifier else {return ItemOutcome(title:item.name,path:item.id,status:"Unavailable",detail:"Finish the current update first, or update Bonsai separately.")}
        do {
            let identity=try Identity.read(url)
            guard !identity.isSymlink,identity.isDirectory,let feed=bundle.infoDictionary?["SUFeedURL"] as? String,let feedURL=URL(string:feed),PublicMetadataHTTP.valid(feedURL) else {throw BonsaiError.refused("The installed application does not declare a supported HTTPS Sparkle feed.")}
            let initialBuild=bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let driver=SPUStandardUserDriver(hostBundle:bundle,delegate:nil)
            let session=SPUUpdater(hostBundle:bundle,applicationBundle:bundle,userDriver:driver,delegate:self)
            updater=session;active=true;finished=false;failure=nil
            progress(SoftwareUpdateProgress(.installing))
            try session.start();session.checkForUpdates()
            let deadline=ProcessInfo.processInfo.systemUptime+1200
            while !finished && ProcessInfo.processInfo.systemUptime<deadline {
                if Task.isCancelled {return ItemOutcome(title:item.name,path:item.id,status:"Pending",detail:"Use Cancel in the Sparkle update window to stop its current download. No installation success is assumed.")}
                try await Task.sleep(nanoseconds:200_000_000)
            }
            if let failure {throw failure}
            progress(SoftwareUpdateProgress(.checking))
            let data=try Data(contentsOf:url.appendingPathComponent("Contents/Info.plist"))
            let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
            let version=info?["CFBundleShortVersionString"] as? String ?? ""
            let build=info?["CFBundleVersion"] as? String ?? ""
            let updated=VersionOrder.newer(version,than:item.installed) || (version==item.installed && VersionOrder.newer(build,than:initialBuild))
            return ItemOutcome(title:item.name,path:item.id,status:updated ? "Updated" : "Pending",detail:updated ? "Installed version verified: "+version : "The installed version has not changed. Finish or cancel the Sparkle update window; no update is counted yet.")
        } catch {active=false;return ItemOutcome(title:item.name,path:item.id,status:"Failed",detail:error.localizedDescription)}
    }
}

#else
@MainActor final class SparkleUpdates {
 static let shared=SparkleUpdates()
 func run(_ item:SoftwareUpdate,progress:SoftwareUpdateProgressHandler={_ in}) async -> ItemOutcome {
  ItemOutcome(title:item.name,path:item.id,status:"Unavailable",detail:"Direct Sparkle installation requires the Developer ID build. Use the publisher app’s updater in this local build.")
 }
}
#endif
