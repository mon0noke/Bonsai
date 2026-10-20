import Foundation

/// An immutable review snapshot keeps results associated with the original app,
/// even after its bundle has disappeared from the live inventory.
public struct UninstallGroup:Identifiable,Sendable {
    public var id:String {physicalURL(app.url).path}
    public let app:InstalledApp
    public let files:[AppAssociatedFile]
    public let selected:Set<String>
    public init(app:InstalledApp,plan:AppRemovalPlan) {self.app=app;files=plan.report.files;selected=plan.selected}
}
public struct UninstallSummary:Sendable {
    public let groups:[UninstallGroup];public let outcomes:[ItemOutcome]
    public init(groups:[UninstallGroup],outcomes:[ItemOutcome]) {self.groups=groups;self.outcomes=outcomes}
    public var removed:Set<String> {Set(outcomes.filter {$0.status=="Trashed"}.map {physicalURL(URL(fileURLWithPath:$0.path)).path})}
    public var removedApps:Int {groups.filter {removed.contains($0.id)}.count}
    public var removedData:Int {removed.subtracting(Set(groups.map(\.id))).count}
    public var failed:Int {outcomes.filter {$0.status != "Trashed" && $0.status != "Cancelled"}.count}
    public var cancelled:Int {outcomes.filter {$0.status=="Cancelled"}.count}
    public var movedBytes:UInt64 {
        var seen=Set<String>()
        return groups.flatMap(\.files).filter {removed.contains($0.id) && seen.insert($0.id).inserted}.reduce(0) {$0+$1.item.measurement.allocated}
    }
    public var headline:String {
        if removed.isEmpty {return cancelled>0 ? "Removal cancelled" : "Files kept in place"}
        if failed>0 || cancelled>0 {return "Removal partly completed"}
        if groups.count==1,removedApps==1 {return groups[0].app.name+" removed"}
        return removedApps>0 ? "\(removedApps) app\(removedApps==1 ? "" : "s") removed" : "Selected app files removed"
    }
}
