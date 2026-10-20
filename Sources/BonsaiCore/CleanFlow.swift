import Foundation

public enum CleanFlow {
    /// An excluded descendant also protects its containing cleanup candidate.
    public static func isGuarded(_ path:String,exclusions:[String])->Bool {
        exclusions.contains { within(path,$0) || within($0,path) }
    }
    /// Preserve the last measurement for guarded rows without scanning exclusions.
    public static func retainingGuards(_ report:CleanReport,previous:[ReviewItem],exclusions:[String])->CleanReport {
        let ids=Set(report.items.map(\.id))
        let retained=previous.filter { !ids.contains($0.id) && isGuarded($0.id,exclusions:exclusions) }
        return CleanReport(items:report.items+retained,issues:report.issues,completeWithinCatalog:report.completeWithinCatalog,deniedDiscoveryPaths:report.deniedDiscoveryPaths)
    }

    // One reviewable report; only proven inventory completeness permits orphan
    // candidates. A locked service-data folder needs no administrator prompt.
    public static func leftovers(home:URL=FileManager.default.homeDirectoryForCurrentUser,roots:[URL]=InstalledIdentifiers.roots,exclusions:[String]=[]) throws -> CleanReport {
        let inventory=try InstalledIdentifiers.snapshot(roots:roots)
        let remnants=try RemnantScanner.scan(home:home,installed:inventory.identifiers,exclusions:exclusions,inventoryComplete:inventory.complete)
        return CleanReport(items:remnants.items,issues:inventory.issues+remnants.issues,completeWithinCatalog:inventory.complete && remnants.completeWithinCatalog,deniedDiscoveryPaths:inventory.blockedPaths+remnants.deniedDiscoveryPaths)
    }
    public static func scan(home:URL=FileManager.default.homeDirectoryForCurrentUser,roots:[URL]=InstalledIdentifiers.roots,exclusions:[String]=[],temporaryRoot:URL=URL(fileURLWithPath:NSTemporaryDirectory()),activity:@escaping @Sendable(CleanScanActivity)->Void={_ in},progress:@Sendable(String,Int)->Void={_,_ in}) throws -> CleanReport {
        var reports=[try CleanCatalog.scan(home:home,exclusions:exclusions,temporaryRoot:temporaryRoot,activity:activity,progress:progress)]
        try Task.checkCancellation();progress("Checking app leftovers",reports[0].items.count)
        activity(CleanScanActivity(location:"Checking app leftovers",allocated:reports[0].items.reduce(0) {$0+$1.measurement.allocated}))
        reports.append(try leftovers(home:home,roots:roots,exclusions:exclusions))
        try Task.checkCancellation()
        let downloads=home.appendingPathComponent("Downloads")
        if FileManager.default.fileExists(atPath:downloads.path) {
            progress("Reviewing old installers",reports.reduce(0) {$0+$1.items.count})
            activity(CleanScanActivity(location:downloads.path,allocated:merge(reports).items.reduce(0) {$0+$1.measurement.allocated}))
            do {reports.append(try InstallerScanner.scan(downloads,exclusions:exclusions))}
            catch is CancellationError {throw CancellationError()}
            catch {reports.append(CleanReport(items:[],issues:["Installer discovery unavailable: "+error.localizedDescription],completeWithinCatalog:false,deniedDiscoveryPaths:FileAccess.deniedURL(error,fallback:downloads).map {[$0.path]} ?? []))}
        }
        try Task.checkCancellation()
        let report=merge(reports)
        activity(CleanScanActivity(location:"Preparing your results",allocated:report.items.reduce(0) {$0+$1.measurement.allocated}))
        return report
    }
    public static func merge(_ reports:[CleanReport])->CleanReport {
        var retained:[ReviewItem]=[]
        for item in reports.flatMap(\.items).sorted(by:{$0.id.count==$1.id.count ? $0.id<$1.id : $0.id.count<$1.id.count}) {
            if !retained.contains(where:{within(item.id,$0.id)}) {retained.append(item)}
        }
        return CleanReport(items:retained,issues:reports.flatMap(\.issues),completeWithinCatalog:reports.allSatisfy(\.completeWithinCatalog),deniedDiscoveryPaths:reports.flatMap(\.deniedDiscoveryPaths))
    }
    public static func recommended(_ items:[ReviewItem],runningIDs:Set<String>)->Set<String> {
        Set(items.filter {$0.measurement.manifest[$0.id]?.owner==getuid() && $0.readOnlyReason==nil && $0.category != "Trash" && $0.measurement.complete && $0.absentBundleID==nil && ["Low","Review"].contains($0.risk) && !ApplicationActivity.isRunning($0.runningIDs,among:runningIDs)}.map(\.id))
    }
    public static func category(_ name:String)->String {
        switch name {
        case "Application caches","Communication","Design tools","Games & media","Productivity":return "App Caches"
        case "Developer artifacts":return "Developer Tools"
        case "AI tools":return "AI Tools"
        case "Cloud clients":return "Cloud Storage"
        case "Temporary files":return "Temporary Files"
        case "Potential app leftovers":return "Uninstalled App Leftovers"
        case "Old installers":return "Installers"
        default:return name
        }
    }
    public static let categoryOrder=["App Caches","System Caches","Logs","Misc","Temporary Files","Developer Tools","AI Tools","Browsers","Cloud Storage","Uninstalled App Leftovers","Installers","Dependency folders","Trash"]
}
