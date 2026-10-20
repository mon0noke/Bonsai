import SwiftUI
import AppKit
import BonsaiCore

@MainActor final class SoftwareStore:ObservableObject {
    enum Detail { case queued,loading,loaded,failed(String) }
    typealias Scanner = @Sendable (InstalledApp,[InstalledApp],PathPolicy) async throws -> AppAssociationReport
    @Published var sort:AppSortOrder
    @Published var includeSystem:Bool { didSet { defaults?.set(includeSystem,forKey:"softwareIncludeSystem") } }
    @Published private(set) var chosen=Set<String>()
    @Published private(set) var expanded=Set<String>()
    @Published private(set) var plans:[String:AppRemovalPlan]=[:]
    @Published private(set) var details:[String:Detail]=[:]
    private let defaults:UserDefaults?
    private let scanner:Scanner
    private var waiting:[(InstalledApp,[InstalledApp],PathPolicy)]=[]
    private var active:[String:Task<Void,Never>]=[:]
    private var generation=UUID()
    private var icons:[String:NSImage]=[:]
    init(defaults:UserDefaults? = .standard,scanner:@escaping Scanner = { app,inventory,policy in
        let protected=try await ProtectionBackend.protectedIdentifiers([app.bundleID])
        guard protected.isEmpty else {return AppAssociationReport(appID:app.id,files:[],issues:["Bonsai protects this system or vendor-managed application. Use System Settings or its official uninstaller."])}
        return try AppInventory.associationReport(app,inventory:inventory,policy:policy) }) {
        self.defaults=defaults;self.scanner=scanner
        let field=AppSortField(rawValue:defaults?.string(forKey:"softwareSortField") ?? "") ?? .name
        sort=AppSortOrder(field:field,ascending:defaults?.object(forKey:"softwareSortAscending") as? Bool ?? (field == .name))
        includeSystem=defaults?.bool(forKey:"softwareIncludeSystem") ?? false
    }
    func chooseSort(_ field:AppSortField) {
        sort.choose(field);defaults?.set(sort.field.rawValue,forKey:"softwareSortField");defaults?.set(sort.ascending,forKey:"softwareSortAscending")
    }
    private var presentationKey:String?
    private var presentation:[InstalledApp]=[]
    func visible(_ apps:[InstalledApp],query:String,revision:Int?=nil) -> [InstalledApp] {
        let key=revision.map { "\($0)|\(query)|\(sort.field)|\(sort.ascending)|\(includeSystem)" }
        if let key,key==presentationKey { return presentation }
        let result=sort.sorted(apps.filter { (includeSystem || !within($0.id,"/System")) && (query.isEmpty || ($0.name+" "+$0.bundleID+" "+$0.id).localizedCaseInsensitiveContains(query)) })
        presentationKey=key;presentation=result;return result
    }
    func icon(_ app:InstalledApp)->NSImage {
        if let image=icons[app.id] { return image }
        if icons.count>=256 { icons.removeAll() }
        let image=NSWorkspace.shared.icon(forFile:app.url.path);icons[app.id]=image;return image
    }
    func toggleApp(_ app:InstalledApp,inventory:[InstalledApp],policy:PathPolicy) {
        if chosen.contains(app.id) { chosen.remove(app.id);expanded.remove(app.id);plans[app.id]?.clear() }
        else {
            chosen.insert(app.id)
            if let report=plans[app.id]?.report { plans[app.id]=AppRemovalPlan(report:report,selectDefaults:true) }
            load(app,inventory:inventory,policy:policy)
        }
    }
    /// Row clicks select once, then only change disclosure. The group checkbox deselects.
    func activateApp(_ app:InstalledApp,inventory:[InstalledApp],policy:PathPolicy) {
        if chosen.contains(app.id) { toggleExpanded(app,inventory:inventory,policy:policy) }
        else { toggleApp(app,inventory:inventory,policy:policy) }
    }
    func toggleExpanded(_ app:InstalledApp,inventory:[InstalledApp],policy:PathPolicy) {
        guard chosen.contains(app.id) else { return }
        if expanded.contains(app.id) { expanded.remove(app.id) }
        else { expanded.insert(app.id);load(app,inventory:inventory,policy:policy) }
    }
    func load(_ app:InstalledApp,inventory:[InstalledApp],policy:PathPolicy,refresh:Bool=false) {
        guard active[app.id]==nil,!waiting.contains(where:{$0.0.id==app.id}) else { return }
        if !refresh,let plan=plans[app.id],Date().timeIntervalSince(plan.report.date)<300 { return }
        details[app.id] = .queued;waiting.append((app,inventory,policy));pump()
    }
    private func pump() {
        while active.count<2,!waiting.isEmpty {
            let (app,inventory,policy)=waiting.removeFirst();let token=generation;let scanner=self.scanner
            details[app.id] = .loading
            active[app.id]=Task { [weak self] in
                let worker=Task.detached(priority:.utility) { try await scanner(app,inventory,policy) }
                let result=await withTaskCancellationHandler(operation:{ await worker.result },onCancel:{worker.cancel()})
                guard let self,self.generation==token else { return }
                self.active.removeValue(forKey:app.id)
                if Task.isCancelled { self.details[app.id] = .failed("Inspection cancelled. Retry when ready.");self.pump();return }
                switch result {
                case .success(let report):
                    self.plans[app.id]=AppRemovalPlan(report:report,selectDefaults:self.chosen.contains(app.id),retaining:self.plans[app.id]?.selected)
                    self.details[app.id] = .loaded
                case .failure(let error):self.details[app.id] = .failed(error is CancellationError ? "Inspection cancelled. Retry when ready." : error.localizedDescription)
                }
                self.pump()
            }
        }
    }
    func cancelInspection(_ id:String) {
        waiting.removeAll { $0.0.id==id }
        active[id]?.cancel()
        if active[id]==nil { details[id] = .failed("Inspection cancelled. Retry when ready.") }
    }
    func setFile(_ id:String,appID:String,selected:Bool) {
        plans[appID]?.set(id,selected:selected)
        if plans[appID]?.selected.isEmpty==false { chosen.insert(appID) }
    }
    func setReviewGroup(_ appID:String,selected:Bool) {
        plans[appID]?.setReviewGroup(selected)
        if plans[appID]?.selected.isEmpty==false { chosen.insert(appID) }
    }
    var selectedItems:[ReviewItem] {
        var seen=Set<String>()
        return plans.keys.sorted().flatMap { plans[$0]?.items ?? [] }.filter { seen.insert($0.id).inserted }
    }
    var inspectionsPending:Bool { chosen.contains { id in active[id] != nil || waiting.contains(where:{$0.0.id==id}) } }
    var selectedBytes:UInt64 { selectedItems.reduce(0) { $0+$1.measurement.allocated } }
    func clear() { chosen=[];expanded=[];for id in plans.keys { plans[id]?.clear() } }
    func invalidate() {
        presentationKey=nil;presentation=[];generation=UUID();active.values.forEach { $0.cancel() };active=[:];waiting=[];plans=[:];details=[:];chosen=[];expanded=[];icons=[:]
    }
    func consume(_ outcomes:[ItemOutcome]) {
        let removed=Set(outcomes.filter { $0.status=="Trashed" }.map(\.path))
        for id in plans.keys where plans[id]?.report.files.contains(where:{removed.contains($0.id)})==true { plans.removeValue(forKey:id);details.removeValue(forKey:id);chosen.remove(id);expanded.remove(id) }
    }
}
