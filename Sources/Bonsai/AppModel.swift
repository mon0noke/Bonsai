import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import BonsaiCore

@MainActor final class AppModel: ObservableObject {
    let software=SoftwareStore()
    let updateStore=SoftwareUpdatesStore()
    @Published var loginEntries:[LoginEntry]=[]
    @Published var loginNote="Read login items to include macOS-managed registrations."
    @Published var loginRead=false
    @Published var loginDate:Date?
    @Published var loginNeedsRefresh=false
    @Published var startupLoading=false
    @Published var startupNote=""
    private var startupTask:Task<Void,Never>?
    private var startupGeneration=UUID()
    @Published var runningAppIDs=Set<String>()
    enum Page: String, CaseIterable { case clean="Clean",software="Software",optimize="Optimize",analyze="Analyze",status="Status"
        var symbol: String { switch self { case .clean: return "sparkles"; case .software: return "square.stack.3d.up"; case .analyze: return "square.grid.2x2"; case .optimize: return "slider.horizontal.3"; case .status: return "waveform.path.ecg" } }
    }
    enum CleanMode:String,CaseIterable { case caches="Caches",remnants="App leftovers",installers="Installers",projects="Projects" }
    @Published var cleanScanAllocated:UInt64?
    @Published var cleanMode:CleanMode = .caches
    @Published var trashNotices:[TrashAppNotice]=[]; @Published var trashWatchNote=""; @Published var trashWatchNeedsAccess=false; @Published var operationKind=""
    private var reports:[CleanMode:CleanReport]=[:]; private var reportDates:[CleanMode:Date]=[:]
    @Published var accessRequest:FileAccessNeed?
    @Published var accessMessage=""
    enum AccessRetry {case caches,remnants,installers(URL),projects(URL),disk}
    private var accessRetry:AccessRetry?
    private var permissionFolder:URL?
    private var cleanScopeRoot:URL?
    @Published var maintenanceSelection=Set(MaintenanceTask.catalog.filter {$0.recommended && $0.available}.map(\.id))
    @Published var maintenanceTasks:[MaintenanceTask]=[]
    @Published var maintenanceOutcomes:[ItemOutcome]=[]
    @Published var maintenanceActive:String?
    @Published var maintenanceDate:Date?
    @Published var maintenanceCancelled=false
    enum MaintenanceScreen {case overview,run,complete,details}
    @Published var maintenanceScreen:MaintenanceScreen = .overview
    enum UninstallScreen {case list,run,complete,details}
    @Published var uninstallScreen:UninstallScreen = .list
    @Published var uninstallGroups:[UninstallGroup]=[]
    @Published var uninstallOutcomes:[ItemOutcome]=[]
    @Published var uninstallCurrent:String?
    @Published var uninstallIndex=0
    @Published var uninstallDate:Date?
    @Published var inventoryBusy=false
    @Published var inventoryProgress=""
    private var inventoryTask:Task<Void,Never>?
    private var inventoryGeneration=UUID()
    private(set) var inventoryRevision=0
    @Published var requestedUtility:String?
    @Published var softwareTab="Uninstall"
    @Published var accessoryBatteries:[(String,Int)]=[]
    @Published var page: Page = .clean
    @Published var cleanItems: [ReviewItem] = []; @Published var selected = Set<String>(); @Published var exclusions: [String] = UserDefaults.standard.stringArray(forKey:"exclusions") ?? []
    @Published var preparedInstallers:[String:URL]=[:]
    @Published var busy = false; @Published var progress = ""; @Published var error: String?; @Published var results: [ItemOutcome] = []; @Published var resultTitle = ""; @Published var showResults = false
    @Published var review: [ReviewItem] = []; @Published var showReview = false; @Published var reviewTitle = "Review cleanup"; @Published var reviewSelection = Set<String>()
    @Published var inventoryNote="Inventory not scanned. Depth: three folders beneath each supported root."
    @Published var apps: [InstalledApp] = [] {didSet {inventoryRevision += 1}}; @Published var updates: [SoftwareUpdate] = []; @Published var startup: [StartupItem] = []; @Published var updateNote = "Check declared appcasts, public App Store metadata and Homebrew with network consent."
    @Published var diskScanning=false
    @Published var diskProgress=""
    private var diskTask:Task<Void,Never>?
    private var diskGeneration=UUID()
    private var diskPermissionFolder:URL?
    typealias DiskScanOverride = @Sendable (URL,Bool,DiskScope) async throws -> DiskScan
    private let diskScanOverride:DiskScanOverride?
    @Published var disk: DiskScan?; @Published var diskRoot = URL(fileURLWithPath:"/"); @Published var diskOverview=true; @Published var diskNote=""; @Published var diskIncremental: [DiskEntry] = []
    @Published var dialogTokens=Set<UUID>()
    @Published var inspectedProcess:ProcessGroup?
    @Published var diskAction:DiskEntry?
    @Published var diskTrashOutcome:ItemOutcome?
    @Published var telemetryLoading=true
    @Published var gpuHistory:[Double]=[]
    @Published var snapshot=TelemetrySnapshot(); @Published var cpuHistory: [Double] = []; @Published var memoryHistory: [Double] = []; @Published var networkHistory: [Double] = []; @Published var networkUploadHistory: [Double] = []
    @Published var history:[AuditEntry]=[]; @Published var pinned=Set(UserDefaults.standard.stringArray(forKey:"pinnedProcesses") ?? [])
    @Published var awakeDeadline:Date?; private var awakeTimer:Timer?
    @Published var keepAwake = false; @Published var lastScan: Date?; @Published var scanNote = "Each scan phase is bounded. Unreadable, excluded, or unvisited locations are not reported as empty."
    let alerts=PreferenceAlerts()
    let audit=AuditStore(); let explorer=DiskExplorer(storage:.application); let telemetry=TelemetryCollector(); let power=PowerAssertion(); let screen=ScreenCurtain()
    private var lastDailyUpdateAttempt:Date?
    private var operation: Task<Void,Never>?; private var sampler: Task<Void,Never>?; private var generation=UUID()
    init(startServices:Bool=true,diskScanOverride:DiskScanOverride?=nil) {
        self.diskScanOverride=diskScanOverride
        if let data=UserDefaults.standard.data(forKey:"loginInventorySnapshot"),data.count<=262_144,let snapshot=try? JSONDecoder().decode(LoginInventorySnapshot.self,from:data) {
            loginEntries=snapshot.currentUser();loginDate=snapshot.date;loginRead=true;loginNeedsRefresh=true
            loginNote="Saved login items. Refresh to verify current macOS state."
        }
        guard startServices else {telemetryLoading=false;return}
        sampler=Task { [weak self] in
            guard let self else { return }
            var samples=0
            while !Task.isCancelled {
                let sample=await telemetry.sample(applications:Self.processApplications(),includeSystemMetrics:page == .status && !NSApp.isHidden && NSApp.windows.contains(where:{$0.isVisible && !$0.isMiniaturized})); snapshot=sample;telemetryLoading=false
                let running=Self.runningBundleIDs();if running != runningAppIDs { runningAppIDs=running }
                if let gpu=sample.gpu.utilization {gpuHistory.append(gpu);gpuHistory=Array(gpuHistory.suffix(60))} else {gpuHistory=[]}
                if let cpu=sample.cpu { cpuHistory.append(cpu); cpuHistory=Array(cpuHistory.suffix(60)) }
                memoryHistory.append(sample.memoryTotal>0 ? Double(sample.memoryUsed)/Double(sample.memoryTotal)*100 : 0); memoryHistory=Array(memoryHistory.suffix(60))
                networkHistory.append(sample.networks.first(where: { $0.interface.hasPrefix("en") })?.download ?? 0); networkHistory=Array(networkHistory.suffix(60))
                networkUploadHistory.append(sample.networks.first(where: { $0.interface.hasPrefix("en") })?.upload ?? 0); networkUploadHistory=Array(networkUploadHistory.suffix(60))
                samples += 1
                let bluetoothEnabled=UserDefaults.standard.bool(forKey:"bluetoothAlerts")
                let accessories=(bluetoothEnabled || page == .status) && samples%15==1 ? await Task.detached {ConnectedAccessories.read()}.value : nil
                if let accessories {accessoryBatteries=accessories}
                alerts.observe(sample,accessories:accessories,userActive:MacActivity.isActive)
                if samples % 30==1 {checkDailyUpdatesIfNeeded()}
                if samples % 15==1,UserDefaults.standard.bool(forKey:"watchTrashApps") {
                    await refreshTrashWatch()
                }
                try? await Task.sleep(nanoseconds:2_000_000_000)
            }
        }
        Task {
            history=await audit.read();updateStore.restoreUpdateOutcomes(history);await alerts.refreshAuthorization();await alerts.removeObsoleteNotifications()
            if ProcessInfo.processInfo.arguments.contains("--preview-notifications") {await alerts.previewNotifications()}
        }
    }
    func refreshTrashWatch() async {
        guard UserDefaults.standard.bool(forKey:"watchTrashApps") else {return}
        let result=await Task.detached(priority:.utility) {Result {try TrashAppMonitor.inspect()}}.value
        switch result {
        case .success(let notices):alerts.observeTrash(notices);trashNotices=notices;trashWatchNote="";trashWatchNeedsAccess=false
        case .failure(let error):
            trashWatchNeedsAccess=FileAccess.isPermission(error)
            trashWatchNote=trashWatchNeedsAccess ? "Full Disk Access is needed to check Trash." : "Could not check Trash: \(error.localizedDescription)"
        }
    }
    func shutdown() { diskGeneration=UUID();diskTask?.cancel();diskTask=nil;diskScanning=false;diskProgress="";diskPermissionFolder?.stopAccessingSecurityScopedResource();diskPermissionFolder=nil;permissionFolder?.stopAccessingSecurityScopedResource();permissionFolder=nil;startupTask?.cancel();updateStore.cancel();inventoryTask?.cancel();software.invalidate();sampler?.cancel(); operation?.cancel(); awake(false); screen.stop() }
    func begin(_ text: String, kind:String="general", body: @escaping @MainActor (UUID) async -> Void) {
        guard !busy else { error="Another operation is in progress. Cancel it or wait for its results."; return }
        let token=UUID(); generation=token; busy=true; operationKind=kind; progress=text; error=nil;cleanScanAllocated=nil
        operation=Task { await body(token); if self.generation==token { self.busy=false; self.progress=""; self.operationKind="";self.permissionFolder?.stopAccessingSecurityScopedResource();self.permissionFolder=nil } }
    }
    func cancel() { if page == .analyze && diskScanning {cancelDisk()} else {cancelForeground()} }
    func cancelForeground() {operation?.cancel();progress=["startup-read","clean-access"].contains(operationKind) ? "Cancel the macOS approval sheet to finish cancelling…" : "Cancelling…"}
    func scanClean() {
        setCleanMode(.caches)
        begin("Discovering generated files…",kind:"clean") { token in
            do {
                let exclusions=self.exclusions
                let worker=Task.detached(priority:.utility) { try CleanFlow.scan(exclusions:exclusions,activity:{activity in Task { @MainActor in if self.generation==token && self.busy && self.operationKind=="clean" && self.operation?.isCancelled != true { self.progress=activity.location;self.cleanScanAllocated=activity.allocated } } }) }
                let items=try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() })
                try Task.checkCancellation(); guard self.generation==token else { return }
                self.storeReport(items,mode:.caches)
            } catch { if self.generation==token {self.handleAccess(error,retry:.caches,operation:"Clean scan")} }
        }
    }
    var cleanComplete:Bool? { reports[cleanMode]?.completeWithinCatalog }
    func setCleanMode(_ mode:CleanMode) {
        cleanMode=mode;cleanItems=reports[mode]?.items ?? [];lastScan=reportDates[mode];selected=[]
        if let report=reports[mode] {
            let partial=report.items.filter { !$0.measurement.complete }
            let details=partial.prefix(30).map { $0.title+": "+$0.measurement.issues.prefix(3).joined(separator:"; ") }
            scanNote=(report.completeWithinCatalog ? "Complete within selected scope." : "Partial scan: \(partial.count) paths have incomplete measurements.")+"\n"+(report.issues+details).joined(separator:"\n")
        } else { scanNote="Ready to scan. No files change during discovery." }
    }
    func storeReport(_ report:CleanReport,mode:CleanMode) {
        let report=CleanFlow.retainingGuards(report,previous:reports[mode]?.items ?? [],exclusions:exclusions)
        reports[mode]=report; reportDates[mode]=Date()
        if cleanMode==mode {
            setCleanMode(mode)
            if mode == .caches {
                switch UserDefaults.standard.string(forKey:"selectionDefault") {
                case "None","Nothing selected":break
                case "Low-risk logs":selected=Set(report.items.filter {!isGuarded($0) && $0.risk=="Low" && $0.measurement.complete && !ApplicationActivity.isRunning($0.runningIDs,among:Self.runningBundleIDs())}.map(\.id))
                default:restoreRecommendedClean()
                }
            }
        }
        // Readable results stay on screen. Privacy settings are opened only
        // when the user chooses Resolve access, never for skipped inventory.

    }
    func scanCurrentClean() { switch cleanMode { case .caches:scanClean();case .remnants:scanRemnants();case .installers:scanInstallers();case .projects:chooseDependencies() } }
    func scanRemnants() {
        setCleanMode(.remnants)
        begin("Checking installed application identities…",kind:"clean") { token in
            do {
                let exclusions=self.exclusions
                let worker=Task.detached {try CleanFlow.leftovers(exclusions:exclusions)}
                let report=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation();if self.generation==token {self.storeReport(report,mode:.remnants)}
            } catch {if self.generation==token {self.handleAccess(error,retry:.remnants,operation:"App discovery",inventory:true)}}
        }
    }
    func scanInstallers() {
        chooseFolder("Choose Downloads or a folder containing old installers") { [weak self] root in
            guard let self,let root else { return };self.scanInstallers(in:root)
        }
    }
    private func scanInstallers(in root:URL) {
        cleanScopeRoot=root
        setCleanMode(.installers)
        begin("Reviewing old installers…",kind:"clean") { token in
            do { let exclusions=self.exclusions; let worker=Task.detached { try InstallerScanner.scan(root,exclusions:exclusions) }; let report=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()}); try Task.checkCancellation(); if self.generation==token { self.storeReport(report,mode:.installers) } } catch {if self.generation==token {self.handleAccess(error,retry:.installers(root),operation:"Installer scan",fallback:root)}}
        }
    }
    var canNavigateDisk:Bool { true }
    func handoffUpdate(_ item:SoftwareUpdate) { if item.source=="App Store" { if let url=item.sourceURL,var components=URLComponents(url:url,resolvingAgainstBaseURL:false),components.host=="apps.apple.com" {components.scheme="macappstore";open(components.url ?? URL(string:"macappstore://showUpdatesPage")!)} else {open(URL(string:"macappstore://showUpdatesPage")!)} } else if ["Homebrew tap","Website","Homebrew catalog"].contains(item.source),let url=item.sourceURL {open(url)} else if let url=item.applicationURL { open(url) } else { error="Open the publisher's application to use its supported updater." } }
    func chooseDependencies() {
        chooseFolder("Choose a project folder to review dependency artifacts") { [weak self] root in
            guard let self,let root else { return };self.scanDependencies(in:root)
        }
    }
    private func scanDependencies(in root:URL) {
        cleanScopeRoot=root
        setCleanMode(.projects)
        begin("Reviewing project artifacts…",kind:"clean") { token in
            do {
                let worker=Task.detached { try CleanCatalog.dependencyReport(in:root) }
                let items=try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() }); try Task.checkCancellation()
                if self.generation==token { self.setCleanMode(.projects); self.storeReport(items,mode:.projects) }
            } catch {if self.generation==token {self.handleAccess(error,retry:.projects(root),operation:"Project scan",fallback:root)}}
        }
    }
    var reviewIsTrashPurge:Bool {!review.isEmpty && review.allSatisfy {$0.category=="Trash"}}
    var reviewHasPermanentCaches:Bool {UserDefaults.standard.string(forKey:"cacheRemoval")==CacheRemovalMode.permanent.rawValue && review.contains {reviewSelection.contains($0.id) && CacheRemovalPolicy.permits($0)}}
    var reviewIsPermanent:Bool {reviewIsTrashPurge || reviewHasPermanentCaches}
    func prepareReview(_ items:[ReviewItem],title:String,selection:Set<String>?=nil,direct:Bool=false) {
        guard !busy else {return}
        guard !items.isEmpty else {error="Select at least one item to remove.";return}
        review=items;reviewTitle=title
        reviewSelection=(selection ?? Set(items.map(\.id))).intersection(Set(items.filter {!isGuarded($0)}.map(\.id)))
        if direct && !reviewIsPermanent {removeReviewed()} else {showReview=true}
    }
    func removeReviewed(dryRun: Bool = false) {
        let items=review.filter { reviewSelection.contains($0.id) && !isGuarded($0) }; guard !items.isEmpty else { return }; let permanent=reviewIsTrashPurge;let permanentCaches=reviewHasPermanentCaches; showReview=false
        let reportTitle=dryRun ? "Cleanup preview":"Removal report"
        begin(dryRun ? "Validating preview…" : permanent ? "Emptying reviewed Trash items…" : "Revalidating files before Trash…") { _ in
            let exclusions=self.exclusions;let standard=PathPolicy.standard;let policy=PathPolicy(roots:standard.roots,protected:standard.protected+exclusions.map { URL(fileURLWithPath:$0) },uid:standard.uid)
            let worker=Task.detached(priority:.utility) {
                if permanent {return await TrashPurge.perform(items,exclusions:exclusions,confirmed:true,dryRun:dryRun)}
                return await TrashService.perform(items,policy:policy,runningIDs:{ Self.runningBundleIDs() },dryRun:dryRun,permanentCaches:permanentCaches,confirmed:true,absenceValidator:{try InstalledIdentifiers.verifyAbsent($0)})
            }
            let outcomes=await withTaskCancellationHandler(operation:{ await worker.value },onCancel:{ worker.cancel() })
            let removed=Set(outcomes.filter { ["Trashed","Deleted"].contains($0.status) }.map(\.path))
            self.software.consume(outcomes)
            self.cleanItems.removeAll { removed.contains($0.id) }; self.apps.removeAll { removed.contains($0.id) }; self.selected.subtract(removed)
            for (mode,report) in self.reports { self.reports[mode]=CleanReport(items:report.items.filter { !removed.contains($0.id) },issues:report.issues,completeWithinCatalog:report.completeWithinCatalog,deniedDiscoveryPaths:report.deniedDiscoveryPaths) }
            await self.record(reportTitle,outcomes,present:dryRun)
            if outcomes.contains(where: { ["Trashed","Deleted"].contains($0.status) }) { await self.invalidateDiskMeasurements() }
        }
    }
    nonisolated static func runningBundleIDs() -> Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    func cancelInventory() {
        inventoryGeneration=UUID();inventoryTask?.cancel();inventoryBusy=false
        inventoryProgress="";inventoryNote="Sizing stopped. Listed apps remain usable; unmeasured sizes are unknown. Refresh to finish."
    }
    func inventoryApps() {
        guard !busy else {error="Wait for the current operation before refreshing apps.";return}
        inventoryTask?.cancel();let token=UUID();inventoryGeneration=token
        software.invalidate();inventoryBusy=true;inventoryProgress="Reading applications…"
        inventoryTask=Task {
            do {
                let worker=Task.detached(priority:.utility) {try AppInventory.inspect(measureSizes:false)}
                let report=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation();guard self.inventoryGeneration==token else {return}
                self.apps=report.apps;self.inventoryNote=(report.complete ? "Inventory complete within configured roots and depth." : "Partial inventory.")+" "+report.issues.joined(separator:"\n")
                let count=report.apps.count
                self.inventoryProgress="Measuring sizes · 0 / \(count)"
                let sizing=Task.detached(priority:.utility) {
                    try await AppSizePipeline.run(report.apps) {app,finished in
                        await MainActor.run {
                            guard self.inventoryGeneration==token,let index=self.apps.firstIndex(where:{$0.id==app.id}) else {return}
                            self.apps[index]=app;self.inventoryProgress="Measuring sizes · \(finished) / \(count)"
                        }
                    }
                }
                let finished=try await withTaskCancellationHandler(operation:{try await sizing.value},onCancel:{sizing.cancel()})
                try Task.checkCancellation();guard self.inventoryGeneration==token else {return}
                if finished<count {self.inventoryNote += " Size budget reached; refresh to measure remaining apps."}
            } catch {
                guard self.inventoryGeneration==token else {return}
                self.inventoryNote="Partial inventory: \(error.localizedDescription). Listed apps remain usable. Refresh to retry."
            }
            if self.inventoryGeneration==token {self.inventoryBusy=false;self.inventoryProgress=""}
        }
    }
    func addApp() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.applicationBundle];panel.canChooseDirectories=false;panel.canChooseFiles=true;panel.title="Choose an application to inspect"
        let dialogID=UUID();dialogTokens.insert(dialogID)
        let finished:(NSApplication.ModalResponse)->Void={ [weak self] response in
            guard let self else {return};self.dialogTokens.remove(dialogID)
            if response == .OK,let url=panel.url {self.inspectChosenApplication(url)}
        }
        if let window=NSApp.keyWindow {panel.beginSheetModal(for:window,completionHandler:finished)}
        else {panel.begin(completionHandler:finished)}
    }
    private func inspectChosenApplication(_ url:URL) {
        begin("Inspecting chosen application…") { token in
            do { let worker=Task.detached { try AppInventory.scan(roots:[url]) };let items=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation();if self.generation==token { for item in items where !self.apps.contains(where:{$0.id==item.id}) { self.apps.append(item) };if items.isEmpty { self.error="No readable application bundle found. Choose another app or grant access and retry." } } } catch { self.error=error.localizedDescription }
        }
    }
    var softwarePolicy:PathPolicy { let p=PathPolicy.standard;return PathPolicy(roots:p.roots,protected:p.protected+exclusions.map { URL(fileURLWithPath:$0) },uid:p.uid) }
    func removeSoftwareSelection(expected:Set<String>) {
        let items=software.selectedItems
        guard !busy,!software.inspectionsPending,!items.isEmpty else {error="Wait for inspection, then review the selected paths again.";return}
        guard Set(items.map(\.id))==expected else {error="Selection changed. Review the new selection before removing.";return}
        guard !items.contains(where:{ApplicationActivity.isRunning($0.runningIDs,among:Self.runningBundleIDs())}) else {error="Quit the selected applications before removal.";return}
        let groups=apps.compactMap {app -> UninstallGroup? in
            guard let plan=software.plans[app.id],!plan.selected.isEmpty else {return nil}
            return UninstallGroup(app:app,plan:plan)
        }.sorted {$0.id<$1.id}
        guard !groups.isEmpty else {error="Application inventory changed. Refresh before removing.";return}
        let policy=softwarePolicy
        cancelInventory() // Prevent a late size result from resurrecting a removed app.
        uninstallGroups=groups;uninstallOutcomes=[];uninstallCurrent=nil;uninstallDate=nil;uninstallIndex=0;uninstallScreen = .run
        begin("Revalidating selected files…",kind:"uninstall") {token in
            let worker=Task.detached(priority:.utility) {
                do {let protected=try await ProtectionBackend.protectedIdentifiers(groups.map {$0.app.bundleID});guard protected.isEmpty else {throw BonsaiError.refused("Bonsai protects an application in this selection. Refresh the inventory and use its official uninstaller.")}}
                catch {return items.map {ItemOutcome(title:$0.title,path:$0.id,status:"Failed",detail:error.localizedDescription)}}
                return await TrashService.perform(items,policy:policy,runningIDs:{Self.runningBundleIDs()},progress:{index,item,outcomes in
                    await MainActor.run {
                        guard self.generation==token else {return}
                        self.uninstallCurrent=item.id;self.uninstallIndex=index;self.uninstallOutcomes=outcomes
                        self.progress="\(index+1) / \(items.count) · \(item.title)"
                    }
                })
            }
            let outcomes=await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
            guard self.generation==token else {return}
            let removed=Set(outcomes.filter {$0.status=="Trashed"}.map(\.path))
            self.software.consume(outcomes);self.apps.removeAll {removed.contains($0.id)}
            self.uninstallOutcomes=outcomes;self.uninstallCurrent=nil;self.uninstallDate=Date();self.uninstallScreen = .list
            await self.record("Uninstall report",outcomes)
            self.alerts.uninstalledApps(groups.filter {removed.contains($0.app.id)}.map {group in
                (name:group.app.name,recovery:outcomes.first {$0.path==group.app.id && $0.status=="Trashed"}?.recovery)
            })
            await self.refreshTrashWatch()
            if !removed.isEmpty {await self.invalidateDiskMeasurements()}
        }
    }
    private func checkDailyUpdatesIfNeeded(now:Date=Date()) {
        guard MacActivity.isActive,updateStore.automatic,alerts.needsDailyUpdates(now:now),!updateStore.checking else {return}
        if let checked=updateStore.date,Calendar.current.isDate(checked,inSameDayAs:now),updateStore.failure==nil {
            alerts.dailyUpdates(count:updateStore.items.count,checkedAt:checked,now:now,userActive:true)
        } else if !busy,lastDailyUpdateAttempt.map({now.timeIntervalSince($0)>=1800}) ?? true {
            lastDailyUpdateAttempt=now
            updateStore.refresh(apps:[],force:true)
        }
    }
    func checkUpdates() { updateStore.refresh(apps:apps) }
    func updateAll(_ items:[SoftwareUpdate]) {
        let items=SoftwareUpdateBatch.plan(items).filter(\.canInstall)
        guard !busy,!items.isEmpty else {return}
        begin("Preparing updates…",kind:"software-updates") {token in
            self.updateStore.queueInstallations(items)
            defer {self.updateStore.clearInstallations()}
            let outcomes=await SoftwareUpdateBatch.run(items,progress:{i,item in await MainActor.run {guard self.generation==token else {return};self.progress="Updating \(item.name) · \(i+1) / \(items.count)"}},install:{item in
                await self.performUpdate(item,token:token)
            },handoff:{_ in false})
            guard self.generation==token else {return};await self.record("Update all",outcomes,present:false)
        }
    }
    func install(_ update:SoftwareUpdate,quitFirst:Bool=false) {
        let redownload=update.source=="App Store" && updateStore.issues[update.id]=="App Store could not start this update."
        begin("Installing \(update.name)…",kind:"software-updates") {token in
            self.updateStore.queueInstallations([update])
            defer {self.updateStore.clearInstallations()}
            if quitFirst,let url=update.applicationURL {
                let running=NSWorkspace.shared.runningApplications.filter {$0.bundleURL.map(physicalURL)==physicalURL(url)}
                for app in running where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {app.terminate()}
                let deadline=ProcessInfo.processInfo.systemUptime+25
                while running.contains(where:{!$0.isTerminated}) && !Task.isCancelled && ProcessInfo.processInfo.systemUptime<deadline {try? await Task.sleep(for:.milliseconds(200))}
            }
            let outcome=await self.performUpdate(update,token:token,redownload:redownload)
            guard self.generation==token else {return}
            await self.record("Software update",[outcome],present:false)
        }
    }
    func updateAppIsRunning(_ item:SoftwareUpdate)->Bool {item.applicationURL.map {url in NSWorkspace.shared.runningApplications.contains {$0.bundleURL.map(physicalURL)==physicalURL(url)}} ?? false}
    func downloadInstaller(_ item:SoftwareUpdate) {
        begin("Downloading \(item.name)…",kind:"software-updates") {token in
            self.updateStore.queueInstallations([item]);defer {self.updateStore.clearInstallations()}
            do {
                let package=try await DirectUpdates.preparePackage(item,progress:{value in Task {@MainActor in guard self.generation==token else {return};self.updateStore.installationProgress(value,for:item.id)}})
                self.preparedInstallers[item.id]=package
            } catch {self.updateStore.recordOutcome(ItemOutcome(title:item.name,path:item.id,status:Task.isCancelled ? "Cancelled":"Failed",detail:error.localizedDescription))}
        }
    }
    func openPreparedInstaller(_ item:SoftwareUpdate) {
        guard let package=preparedInstallers[item.id] else {return}
        begin("Verifying \(item.name)…",kind:"software-updates") {_ in
            do {
                try await DirectUpdates.verifyPackage(package,item:item)
                guard NSWorkspace.shared.open(package) else {throw BonsaiError.unavailable("macOS Installer could not open this package.")}
                self.updateStore.recordOutcome(ItemOutcome(title:item.name,path:item.id,status:"Installer opened",detail:"Finish the macOS installer, then refresh."))
            } catch {self.updateStore.recordOutcome(ItemOutcome(title:item.name,path:item.id,status:"Failed",detail:error.localizedDescription))}
        }
    }
    private func performUpdate(_ item:SoftwareUpdate,token:UUID,redownload:Bool=false) async -> ItemOutcome {
        updateStore.installationProgress(SoftwareUpdateProgress(.preparing),for:item.id)
        defer {updateStore.finishInstallation(item.id)}
        if let url=item.applicationURL,NSWorkspace.shared.runningApplications.contains(where:{$0.bundleURL.map(physicalURL)==physicalURL(url)}) {
            let outcome=ItemOutcome(title:item.name,path:item.id,status:"Needs attention",detail:"Quit this application before replacing it. Other updates continue.")
            updateStore.recordOutcome(outcome);return outcome
        }
        let report:SoftwareUpdateProgressHandler = {[weak self] value in
            Task {@MainActor in
                guard let self,self.generation==token else {return}
                self.updateStore.installationProgress(value,for:item.id)
            }
        }
        let result:ItemOutcome
        if redownload && item.source=="App Store" {result=await StoreUpdates.install(item,consent:true,redownload:true,progress:report)}
        else {result=item.usesSparkle && !item.usesDirectArchive ? await SparkleUpdates.shared.run(item,progress:report) : await UpdateService.install(item,consent:true,progress:report)}
        updateStore.recordOutcome(result)
        if result.status=="Updated" {await refreshUpdatedApp(item)}
        return result
    }
    func refreshUpdatedApp(_ item:SoftwareUpdate) async {
        updateStore.cancel();updateStore.installed(item.id)
        guard let url=item.applicationURL,let app=apps.first(where:{$0.id==physicalURL(url).path}) else {return}
        let refreshed=await Task.detached(priority:.utility) {try? AppInventory.refreshed(app)}.value
        guard let refreshed,let index=apps.firstIndex(where:{$0.id==app.id}) else {return}
        apps[index]=refreshed;software.invalidate()
    }
    func readLoginItems() {
        begin("Waiting for macOS login-item approval…",kind:"startup-read") {_ in
            do {let report=try await LoginItemInventory.readWithAuthorization();try Task.checkCancellation();self.loginEntries=report.entries;self.loginNote=report.note;self.loginRead=true;self.loginDate=Date();self.loginNeedsRefresh=false
                if let data=try? JSONEncoder().encode(LoginInventorySnapshot(entries:report.entries,date:self.loginDate!)),data.count<=262_144 {UserDefaults.standard.set(data,forKey:"loginInventorySnapshot")}}
            catch {self.loginNote=error.localizedDescription;self.error=error.localizedDescription}
        }
    }
    func loginSettings() {
        loginNeedsRefresh=loginRead
        loginNote="Refresh login items after making changes in System Settings."
        SMAppService.openSystemSettingsLoginItems()
    }
    func loadStartup() {
        guard !startupLoading else {return}
        let token=UUID();startupGeneration=token;startupLoading=true
        startupTask=Task {
            do {
                let items=try await StartupService.inventory();try Task.checkCancellation()
                guard startupGeneration==token else {return};startup=items;startupNote=""
            } catch {guard startupGeneration==token else {return};startupNote=error.localizedDescription}
            if startupGeneration==token {startupLoading=false;startupTask=nil}
        }
    }
    func changeStartup(_ item: StartupItem) { begin("Changing and verifying launch state…") { _ in let result=await StartupService.set(item,disabled:item.disabled != true); self.startup=(try? await StartupService.inventory()) ?? self.startup; await self.record("Startup change",[result]) } }
    func chooseDisk() { chooseFolder("Choose a folder to analyze") { [weak self] root in guard let self,let root else { return };self.scanDisk(refresh:true,root:root) } }
    func cancelDisk() {diskTask?.cancel();diskProgress="Stopping…"}
    func scanDisk(refresh: Bool = false, root: URL? = nil, overview:Bool?=nil, askForAccess:Bool=true) {
        diskTask?.cancel()
        let token=UUID();diskGeneration=token
        if let root { diskRoot=root;diskOverview=false }
        if let overview {diskOverview=overview;if overview {diskRoot=URL(fileURLWithPath:"/")}}
        let root=diskRoot,scope:DiskScope=diskOverview ? .overview : .folder
        if disk?.root != physicalURL(root) || disk?.scope != scope {disk=nil}
        diskIncremental=[];diskNote="";diskScanning=true;diskProgress="Measuring locations…"
        diskTask=Task {
            defer {if self.diskGeneration==token {self.diskScanning=false;self.diskProgress="";self.diskTask=nil;self.diskPermissionFolder?.stopAccessingSecurityScopedResource();self.diskPermissionFolder=nil}}
            do {
                if let saved=await self.explorer.saved(root,scope:scope),self.diskGeneration==token {self.disk=saved}
                let value:DiskScan
                if let override=self.diskScanOverride {value=try await override(root,refresh,scope)}
                else {value=try await self.explorer.scan(root,refresh:refresh,scope:scope,progress:{entry,count,total in Task { @MainActor in if self.diskGeneration==token && self.diskScanning && self.disk==nil && self.diskRoot==root {self.diskIncremental.append(entry);self.diskProgress="\(count) / \(total) locations · \(entry.url.lastPathComponent)"} }},activity:{name,count in Task { @MainActor in if self.diskGeneration==token && self.diskScanning && self.diskRoot==root {self.diskProgress="\(name) · \(count.formatted()) items checked"} }})}
                guard self.diskGeneration==token,self.diskRoot==root else {return}
                self.disk=value;self.diskIncremental=[]
                if askForAccess,!value.wasCancelled,let url=FileAccess.preferredDeniedURL(value.accessDeniedPaths),self.page == .analyze {self.requestAccess(url,retry:.disk,operation:"Analyze scan",automatic:true)}
            } catch {if self.diskGeneration==token {
                if let url=FileAccess.deniedURL(error,fallback:root) {if askForAccess && self.page == .analyze {self.requestAccess(url,retry:.disk,operation:"Analyze scan")};self.diskNote="This location needs access. Resolve access and retry."}
                else {self.diskNote=error is CancellationError ? "Scan stopped. Refresh to complete." : error.localizedDescription}
            }}
        }
    }
    private func invalidateDiskMeasurements() async {
        diskGeneration=UUID();diskTask?.cancel();diskTask=nil;diskScanning=false;diskProgress=""
        diskPermissionFolder?.stopAccessingSecurityScopedResource();diskPermissionFolder=nil
        await explorer.invalidate();disk=nil;diskIncremental=[]
    }
    func retryDiskAccess() {Task {await explorer.invalidate();scanDisk(refresh:true)}}
    var cleanAccessPaths:[String] {reports[cleanMode]?.accessDeniedPaths ?? []}
    private func cleanRetry(_ mode:CleanMode)->AccessRetry? {
        switch mode {case .caches:return .caches;case .remnants:return .remnants;case .installers:return cleanScopeRoot.map(AccessRetry.installers);case .projects:return cleanScopeRoot.map(AccessRetry.projects)}
    }
    private func requestAccess(_ url:URL,retry:AccessRetry,operation:String,inventory:Bool=false,automatic:Bool=false) {
        let diskAccess:Bool;if case .disk=retry {diskAccess=true} else {diskAccess=false}
        let token=diskAccess ? diskGeneration:generation
        Task {
            let report=await Task.detached(priority:.utility) {FileAccess.check()}.value
            guard (diskAccess ? diskGeneration:generation)==token else {return}
            if diskAccess && automatic && page != .analyze {return}
            let readable = !report.needsAccess && report.probes.contains {$0.status == .readable}
            let need=FileAccessNeed(url:url,operation:operation,inventory:inventory,privacyReadable:readable)
            if automatic && [FileAccessRoute.systemProtection,.filePermissions,.administrator].contains(need.route) {return}
            accessRetry=retry;accessMessage="";error=nil;accessRequest=need
        }
    }
    private func handleAccess(_ failure:Error,retry:AccessRetry,operation:String,fallback:URL?=nil,inventory:Bool=false) {
        if failure is CancellationError {error="Scan stopped. No files changed; you can scan again.";return}
        if let url=FileAccess.deniedURL(failure,fallback:fallback) {requestAccess(url,retry:retry,operation:operation,inventory:inventory)}
        else {error=failure.localizedDescription}
    }
    func showCleanAccess() {if let url=FileAccess.preferredDeniedURL(cleanAccessPaths),let retry=cleanRetry(cleanMode) {requestAccess(url,retry:retry,operation:"Clean · "+cleanMode.rawValue)}}
    func showDiskAccess() {if let url=FileAccess.preferredDeniedURL(disk?.accessDeniedPaths ?? []) {requestAccess(url,retry:.disk,operation:"Analyze scan")}}
    func retryRequestedAccess() {
        guard let retry=accessRetry else {return}
        if case .disk=retry {} else if busy {return}
        accessRequest=nil;accessMessage=""
        switch retry {case .caches:scanClean();case .remnants:scanRemnants();case .installers(let root):scanInstallers(in:root);case .projects(let root):scanDependencies(in:root);case .disk:retryDiskAccess()}
    }
    var recommendedClean:Set<String> {CleanFlow.recommended(cleanItems.filter {!isGuarded($0)},runningIDs:Self.runningBundleIDs())}
    func restoreRecommendedClean() {selected=recommendedClean}
    func choosePermissionFolder() {
        guard let need=accessRequest else {return}
        if case .disk=accessRetry {} else if busy {return}
        accessRequest=nil
        chooseFolder("Allow access to \(need.url.lastPathComponent) or its parent folder") { [weak self] url in
            guard let self else {return}
            guard let url else {self.accessRequest=need;return}
            guard within(need.url.path,physicalURL(url).path) else {self.accessMessage="Choose the blocked folder or one of its parents.";self.accessRequest=need;return}
            if url.startAccessingSecurityScopedResource() {if case .disk=self.accessRetry {self.diskPermissionFolder=url} else {self.permissionFolder=url}}
            self.retryRequestedAccess()
        }
    }
    func inspectDisk(_ entry:DiskEntry) {diskTrashOutcome=nil;diskAction=entry}
    func closeDiskAction() {
        guard operationKind != "disk-trash" else {return}
        let refresh=diskTrashOutcome?.status=="Trashed"
        diskAction=nil;diskTrashOutcome=nil
        if refresh {scanDisk(refresh:true)}
    }
    func trashDisk(_ entry:DiskEntry) {
        guard !busy else {return}
        begin("Moving to Trash…",kind:"disk-trash") { _ in
            let standard=PathPolicy.standard
            let policy=PathPolicy(roots:standard.roots,protected:standard.protected+self.exclusions.map {URL(fileURLWithPath:$0)},uid:standard.uid)
            let worker=Task.detached(priority:.utility) { () -> ItemOutcome in
                do {return DiskTrash.perform(try DiskTrashRequest(entry),policy:policy,runningApplications:{NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)})}
                catch {return ItemOutcome(title:entry.url.lastPathComponent,path:entry.id,status:"Skipped",detail:error.localizedDescription)}
            }
            let outcome=await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
            self.diskTrashOutcome=outcome
            if outcome.status=="Trashed" {await self.invalidateDiskMeasurements()}
            await self.record("Analyze · Move to Trash",[outcome],present:false)
        }
    }
    func maintain(_ task: MaintenanceTask) { runMaintenance([task]) }
    func optimize() {
        guard !busy else { return }
        let tasks=MaintenanceRunner.quickPlan
        guard !tasks.isEmpty else { error="Routine maintenance commands are unavailable. Open maintenance options to inspect supported tasks.";return }
        runMaintenance(tasks)
    }
    func runMaintenance(_ tasks:[MaintenanceTask]) {
        guard !busy,!tasks.isEmpty else { return }
        maintenanceTasks=tasks;maintenanceOutcomes=[];maintenanceDate=nil;maintenanceCancelled=false;maintenanceScreen = .run
        begin("Preparing maintenance…",kind:"maintenance") { token in
            let outcomes=await MaintenanceRunner.run(tasks,progress:{ index,task,completed in
                await MainActor.run {
                    guard self.generation==token else { return }
                    self.maintenanceActive=task.id;self.maintenanceOutcomes=completed
                    self.progress="\(task.title) · \(index+1) / \(tasks.count)"
                }
            })
            guard self.generation==token else { return }
            self.maintenanceCancelled=Task.isCancelled
            self.maintenanceActive=nil;self.maintenanceOutcomes=outcomes;self.maintenanceDate=Date();self.maintenanceScreen = .complete
            await self.record("Maintenance",outcomes,present:false)
            if outcomes.contains(where:{$0.status=="Completed"}) {await self.invalidateDiskMeasurements()}
        }
    }
    static var doctorTasks:[MaintenanceTask] { MaintenanceTask.catalog.filter { ["spotlight","power"].contains($0.id) } }
    func runDoctor() {
        begin("Running read-only diagnostics…",kind:"doctor") { _ in
            var outcomes:[ItemOutcome]=[]
            for task in Self.doctorTasks {
                if Task.isCancelled { outcomes.append(ItemOutcome(title:task.title,path:task.preview,status:"Skipped",detail:"Diagnostics cancelled before this check began."));continue }
                self.progress=task.title+"…"
                outcomes.append(await task.perform())
            }
            await self.record("Doctor diagnostics",outcomes)
        }
    }
    func terminate(_ process: ProcessSample,force:Bool=false) {
        let signal=force ? "SIGKILL" : "SIGTERM"
        begin(force ? "Force quitting process…" : "Sending graceful termination…") { _ in
            do {
                try TelemetryCollector.terminate(process,force:force)
                try? await Task.sleep(nanoseconds:800_000_000)
                let sample=await self.telemetry.sample(applications:Self.processApplications());self.snapshot=sample
                let alive=sample.processes.contains {$0.id==process.id}
                await self.record("Process control",[ItemOutcome(title:process.name,path:"PID \(process.pid)",status:alive ? "Signal sent" : "Exited",detail:alive ? signal+" sent; this process identity remains active. Refresh to verify again." : "Process no longer present after "+signal+".")])
            } catch {self.error=error.localizedDescription}
        }
    }
    func refreshAccessoryBatteries() async {accessoryBatteries=await Task.detached {ConnectedAccessories.read()}.value}
    func record(_ title:String,_ outcomes:[ItemOutcome],present:Bool=true) async {
        resultTitle=title;results=outcomes;showResults=present
        do {try await audit.append(AuditEntry(operation:title,outcomes:outcomes));history=await audit.read()}
        catch {self.error="Operation finished, but activity could not be saved: \(error.localizedDescription)"}
    }
    func addExclusion(_ url:URL) {
        let path=physicalURL(url).path
        if !exclusions.contains(path) { exclusions.append(path);UserDefaults.standard.set(exclusions,forKey:"exclusions") }
        selected=selected.filter {!CleanFlow.isGuarded($0,exclusions:exclusions)}
        reviewSelection=reviewSelection.filter {!CleanFlow.isGuarded($0,exclusions:exclusions)}
    }
    func isGuarded(_ item:ReviewItem)->Bool {CleanFlow.isGuarded(item.id,exclusions:exclusions)}
    func toggleGuard(_ item:ReviewItem) {
        if exclusions.contains(item.id) {removeExclusion(item.id)}
        else if isGuarded(item) {error="This path is protected by another exclusion. Manage that exclusion in Settings → Exclusions."}
        else {addExclusion(item.url)}
    }
    func removeExclusion(_ value: String) { exclusions.removeAll { $0==value }; UserDefaults.standard.set(exclusions,forKey:"exclusions") }
    static func processApplications()->[ProcessApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in guard let url=app.bundleURL else {return nil};return ProcessApplication(pid:app.processIdentifier,url:url,name:app.localizedName ?? url.deletingPathExtension().lastPathComponent) }
    }
    func togglePin(_ group:ProcessGroup) {
        if pinned.contains(group.pinKey) || pinned.contains(group.name) {pinned.remove(group.pinKey);pinned.remove(group.name)} else {pinned.insert(group.pinKey)}
        UserDefaults.standard.set(Array(pinned),forKey:"pinnedProcesses")
    }
    func togglePin(_ process: ProcessSample) { if pinned.contains(process.name) { pinned.remove(process.name) } else { pinned.insert(process.name) }; UserDefaults.standard.set(Array(pinned),forKey:"pinnedProcesses") }
    func awake(_ enabled:Bool) {
        awakeTimer?.invalidate();awakeTimer=nil;awakeDeadline=nil
        do {try power.set(enabled,behavior:AwakeBehavior(rawValue:UserDefaults.standard.string(forKey:"awakeBehavior") ?? "") ?? .screenAndWork);keepAwake=power.active}
        catch {self.error=error.localizedDescription}
    }
    func awakeFor(_ seconds:TimeInterval?) { awake(true); if let seconds,keepAwake { awakeDeadline=Date().addingTimeInterval(seconds);awakeTimer=Timer.scheduledTimer(withTimeInterval:seconds,repeats:false) { [weak self] _ in Task { @MainActor in self?.awake(false) } } } }
    func chooseFolder(_ title:String,completion:@escaping (URL?)->Void) {
        let panel=NSOpenPanel();panel.message=title
        panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false;panel.allowsOtherFileTypes=true
        let dialogID=UUID();dialogTokens.insert(dialogID)
        let finished:(NSApplication.ModalResponse)->Void={ [weak self] response in self?.dialogTokens.remove(dialogID);completion(response == .OK ? panel.url : nil) }
        if let window=NSApp.keyWindow ?? NSApp.windows.first(where:{$0.isVisible && $0.level == .normal && $0.canBecomeMain}) { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);panel.beginSheetModal(for:window,completionHandler:finished) }
        else { panel.begin(completionHandler:finished) }
    }
    func reveal(_ url:URL) {
        guard url.isFileURL else {error="Choose a local file to reveal in Finder.";return}
        let target=physicalURL(url)
        do {_=try Identity.read(target)} catch {
            self.error="This item is no longer available at its scanned path. Refresh the list and try again.\n"+target.path
            return
        }
        // Let an action's closing overlay finish before Finder comes forward.
        Task { @MainActor in
            await Task.yield()
            NSWorkspace.shared.activateFileViewerSelecting([target])
            NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first?.activate(options:[.activateAllWindows])
        }
    }
    func open(_ url: URL) { if !NSWorkspace.shared.open(url) { error="macOS could not open this location." } }
    func settings(_ anchor: String = "Privacy_AllFiles") { open(URL(string:"x-apple.systempreferences:com.apple.preference.security?"+anchor)!) }
}
