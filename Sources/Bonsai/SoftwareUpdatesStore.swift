import Foundation
import Combine
import BonsaiCore

/// Read-only checks have their own lifecycle so tab navigation and maintenance
/// remain responsive. A generation owns every publication, including cancellation.
@MainActor final class SoftwareUpdatesStore:ObservableObject {
    struct Snapshot:Codable {let items:[SoftwareUpdate];let note:String;let date:Date;let fingerprint:[String];var appStates:[String:String]? = nil;var schema:Int? = 5}
    typealias Check = @Sendable ([InstalledApp],@escaping @Sendable (MetadataCheckReport) async -> Void) async throws -> MetadataCheckReport
    @Published private(set) var items:[SoftwareUpdate]=[]
    @Published private(set) var issues:[String:String]=[:]
    @Published private(set) var installations:[String:SoftwareUpdateProgress]=[:]
    @Published private(set) var appStates:[String:String]=[:]
    @Published private(set) var checking=false
    @Published private(set) var note=""
    @Published private(set) var date:Date?
    @Published private(set) var failure:String?
    @Published private(set) var inspected=0
    @Published var automatic:Bool {didSet {defaults?.set(automatic,forKey:"automaticUpdateChecks");if !automatic {cancel()}}}
    private var task:Task<Void,Never>?
    private var generation=UUID()
    private var fingerprint:[String]=[]
    private var attempt:Date?
    private let defaults:UserDefaults?
    private let check:Check
    init(defaults:UserDefaults? = .standard,check:@escaping Check = {apps,progress in try await SoftwareUpdatesStore.discover(apps,progress:progress)}) {
        self.defaults=defaults;self.check=check
        // The requested product behavior grants metadata-only automatic checks.
        // An explicit opt-out survives upgrades and disables all automatic traffic.
        automatic=defaults?.object(forKey:"automaticUpdateChecks") as? Bool ?? true
        if let data=defaults?.data(forKey:"softwareUpdateSnapshot"),data.count<1_048_576,let cache=try? JSONDecoder().decode(Snapshot.self,from:data),cache.schema==5 {
            items=cache.items;note=cache.note;date=cache.date;fingerprint=cache.fingerprint;appStates=cache.appStates ?? [:]
        }
    }
    nonisolated static func discover(_ apps:[InstalledApp],progress:@escaping @Sendable (MetadataCheckReport) async -> Void) async throws -> MetadataCheckReport {
        async let brew:([SoftwareUpdate],String)=catalogSafely(apps)
        let metadata=try await UpdateDiscovery.check(apps,consent:true,publicCatalogConsent:UserDefaults.standard.bool(forKey:"publicCaskCatalogConsent"),progress:progress)
        let (casks,brewNote)=await brew
        return MetadataCheckReport(updates:BrewCatalog.merge(metadata.updates+casks,preferInstallable:true),notes:metadata.notes+[brewNote],checked:metadata.checked,appStates:metadata.appStates)
    }
    nonisolated private static func catalogSafely(_ apps:[InstalledApp]) async -> ([SoftwareUpdate],String) {
        do {return try await UpdateService.catalog(apps:apps)} catch {return ([],"Homebrew check failed: "+error.localizedDescription)}
    }
    nonisolated static func deduplicate(_ items:[SoftwareUpdate])->[SoftwareUpdate] {
        var seen=Set<String>();return items.filter {seen.insert($0.id).inserted}.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    func enter(apps:[InstalledApp]) {guard automatic else {return};refresh(apps:apps,force:false)}
    func refresh(apps:[InstalledApp],force:Bool=true) {
        guard !checking else {return}
        let signature=apps.map {$0.bundleID+"|"+$0.version+"|"+$0.id}.sorted()
        if !force {
            if let date,(0..<1800).contains(Date().timeIntervalSince(date)),signature==fingerprint {return}
            if let attempt,Date().timeIntervalSince(attempt)<60 {return}
        }
        let token=UUID();generation=token;checking=true;failure=nil;inspected=0;attempt=Date()
        task=Task { [weak self] in
            guard let self else {return}
            do {
                let inventory:[InstalledApp]
                if apps.isEmpty {
                    let worker=Task.detached(priority:.utility) {try AppInventory.scan(measureSizes:false)}
                    inventory=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                } else {inventory=apps}
                try Task.checkCancellation()
                items=[];appStates=[:] // Do not blend stale availability into a new pass.
                let result=try await check(inventory) {report in
                    await MainActor.run {guard self.generation==token,!Task.isCancelled else {return};self.inspected=report.checked;self.items=BrewCatalog.merge(report.updates,preferInstallable:true);self.appStates=report.appStates ?? [:]}
                }
                try Task.checkCancellation();guard generation==token else {return}
                items=BrewCatalog.merge(result.updates,preferInstallable:true);note=result.notes.joined(separator:"\n");date=Date();inspected=result.checked;appStates=result.appStates ?? [:]
                fingerprint=inventory.map {$0.bundleID+"|"+$0.version+"|"+$0.id}.sorted()
                let cache=Snapshot(items:items,note:note,date:date!,fingerprint:fingerprint,appStates:appStates)
                if let data=try? JSONEncoder().encode(cache),data.count<1_048_576 {defaults?.set(data,forKey:"softwareUpdateSnapshot")}
                checking=false;task=nil
            } catch {
                guard generation==token else {return};checking=false;task=nil
                failure=error is CancellationError ? "Check cancelled. Recent results remain available." : error.localizedDescription
            }
        }
    }
    func cancel() {guard checking else {return};generation=UUID();task?.cancel();task=nil;checking=false;failure="Check cancelled. Recent results remain available."}
    static func shortFailure(_ outcome:ItemOutcome)->String? {
        guard !["Updated","Cancelled","Skipped","Opened updater"].contains(outcome.status) else {return nil}
        if outcome.status=="Installer opened" {return "Finish the macOS installer, then refresh."}
        let detail=outcome.detail.lowercased()
        if detail.contains("quit this app") || detail.contains("quit the app") || detail.contains("app is running") || detail.contains("application is running") {return "Quit the app, then retry."}
        if detail.contains("uninstall script") && detail.contains("does not exist") {return "Homebrew setup is incomplete. Use the installer."}
        if detail.contains("sudo") || detail.contains("permission") || detail.contains("not permitted") {return "Administrator approval is needed."}
        if detail.contains("signature") || detail.contains("publisher") {return "Publisher verification failed."}
        if detail.contains("checksum") {return "Download verification failed. Retry."}
        if detail.contains("no downloads initiated") {return "App Store could not start this update."}
        if detail.contains("account") || detail.contains("sign in") {return "App Store approval may be needed."}
        if detail.contains("timed out") || detail.contains("timeout") {return "Update timed out. Retry."}
        if detail.contains("network") || detail.contains("connection") || detail.contains("offline") {return "Check your connection, then retry."}
        if detail.contains("changed") {return "App changed. Refresh and retry."}
        if detail.contains("version has not changed") {return "Update was not installed. Retry."}
        return "Update failed. Try again."
    }
    func recordOutcome(_ outcome:ItemOutcome) {issues[outcome.path]=Self.shortFailure(outcome)}
    func restoreUpdateOutcomes(_ entries:[AuditEntry]) {
        var seen=Set<String>()
        for entry in entries.sorted(by:{$0.date>$1.date}) where ["Update all","Software update"].contains(entry.operation) {
            for outcome in entry.outcomes where seen.insert(outcome.path).inserted {recordOutcome(outcome)}
        }
    }
    func queueInstallations(_ items:[SoftwareUpdate]) {for item in items {issues[item.id]=nil};installations=Dictionary(items.map {($0.id,SoftwareUpdateProgress(.queued))},uniquingKeysWith:{first,_ in first})}
    func installationProgress(_ value:SoftwareUpdateProgress,for id:String) {
        guard let current=installations[id],value.phase.rawValue>=current.phase.rawValue else {return}
        if value.phase==current.phase,let old=current.fraction,let next=value.fraction,next<old {return}
        installations[id]=value
    }
    func finishInstallation(_ id:String) {installations.removeValue(forKey:id)}
    func clearInstallations() {installations=[:]}
    func installed(_ id:String) {items.removeAll {$0.id==id};date=nil;defaults?.removeObject(forKey:"softwareUpdateSnapshot")}
}
