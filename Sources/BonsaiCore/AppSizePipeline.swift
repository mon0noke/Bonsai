import Foundation

/// Metadata appears first; at most two off-main workers measure bundles.
/// Admission has an overall deadline and each bundle has a separate bounded scan.
public enum AppSizePipeline {
    public typealias Measure = @Sendable (InstalledApp) throws -> InstalledApp
    public static func measure(_ app:InstalledApp) throws -> InstalledApp {
        let identity=try Identity.read(app.url)
        guard let original=app.measurement.manifest[app.id],identity.sameObject(as:original),!identity.isSymlink else { throw BonsaiError.changed("Application changed during inventory. Refresh before selecting.") }
        var size=try FileScanner.measure(app.url,limits:ScanLimits(nodes:30_000,seconds:3))
        guard try Identity.read(app.url).sameObject(as:identity) else { throw BonsaiError.changed("Application was replaced during sizing. Refresh.") }
        size.manifest=[app.id:identity] // Inventory sizes are not removal authorization.
        return InstalledApp(url:app.url,name:app.name,bundleID:app.bundleID,version:app.version,measurement:size,lastUsed:app.lastUsed,appStore:app.appStore,lastUsedSource:app.lastUsedSource,installedDate:app.installedDate,isMenuBarApp:app.isMenuBarApp)
    }
    public static func run(_ apps:[InstalledApp],seconds:Double=90,progress:@escaping @Sendable (InstalledApp,Int) async -> Void = {_,_ in},measure:@escaping Measure = {try AppSizePipeline.measure($0)}) async throws -> Int {
        let deadline=ProcessInfo.processInfo.systemUptime+max(0,seconds)
        return try await withThrowingTaskGroup(of:InstalledApp.self) { group in
            var next=0,finished=0
            func admit() throws {
                try Task.checkCancellation()
                guard next<apps.count,ProcessInfo.processInfo.systemUptime<deadline else {return}
                let app=apps[next];next+=1
                group.addTask {try Task.checkCancellation();let measured=try measure(app);try Task.checkCancellation();return measured}
            }
            try admit();try admit()
            do {
                while let app=try await group.next() {
                    try Task.checkCancellation();finished+=1;await progress(app,finished);try admit()
                }
            } catch {group.cancelAll();throw error}
            return finished
        }
    }
}
