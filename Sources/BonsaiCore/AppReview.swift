import Foundation

public enum AppSortField:String,CaseIterable,Sendable {
    case name,size,lastUsed,installed
    public var title:String { switch self { case .name:return "Name";case .size:return "App size";case .lastUsed:return "Last Used";case .installed:return "Installed" } }
}
public struct AppSortOrder:Sendable {
    public var field:AppSortField; public var ascending:Bool
    public init(field:AppSortField = .name,ascending:Bool = true) { self.field=field;self.ascending=ascending }
    public mutating func choose(_ field:AppSortField) {
        if self.field==field { ascending.toggle() } else { self.field=field;ascending=field == .name }
    }
    public func sorted(_ apps:[InstalledApp]) -> [InstalledApp] {
        apps.sorted { precedes($0,$1,leftName:$0.name,rightName:$1.name,leftID:$0.id,rightID:$1.id) }
    }
    /// Source checks arrive incrementally; display order follows the same
    /// installed metadata as Uninstall, with unknown values last in either direction.
    public func sortedUpdates(_ updates:[SoftwareUpdate],inventory:[InstalledApp])->[SoftwareUpdate] {
        let records=Dictionary(inventory.map {(physicalURL($0.url).path,$0)},uniquingKeysWith:{a,_ in a})
        func record(_ update:SoftwareUpdate)->InstalledApp? {update.applicationURL.flatMap {records[physicalURL($0).path]}}
        return updates.sorted {precedes(record($0),record($1),leftName:$0.name,rightName:$1.name,leftID:$0.id,rightID:$1.id)}
    }
    private func precedes(_ a:InstalledApp?,_ b:InstalledApp?,leftName:String,rightName:String,leftID:String,rightID:String)->Bool {
            var result:ComparisonResult = .orderedSame
            switch field {
            case .name:result=leftName.localizedStandardCompare(rightName)
            case .size:
                let ak=(a?.measurement.files ?? 0)>0,bk=(b?.measurement.files ?? 0)>0
                if ak != bk { return ak } // Unmeasured values always last, in both directions.
                let x=ak ? (a?.measurement.allocated ?? 0):0,y=bk ? (b?.measurement.allocated ?? 0):0
                if x != y { return ascending ? x<y : x>y }
            case .lastUsed,.installed:
                let x=field == .lastUsed ? a?.lastUsed : a?.installedDate
                let y=field == .lastUsed ? b?.lastUsed : b?.installedDate
                if (x == nil) != (y == nil) { return x != nil }
                if let x,let y,x != y { return ascending ? x<y : x>y }
            }
            if result == .orderedSame { result=leftName.localizedStandardCompare(rightName) }
            if result == .orderedSame { return leftID<rightID }
            return field == .name && !ascending ? result == .orderedDescending : result == .orderedAscending
    }
}
public enum AppFileKind:String,Sendable {
    case application="Application",cache="Cache",logs="Logs",temporaryCache="Temporary Cache",preferences="Preferences",savedState="Saved State",support="App Support",http="HTTP Storage",webKit="WebKit Data",helper="Helper Tool",launch="Launch Item"
    public var ready:Bool { [.application,.cache,.temporaryCache,.logs].contains(self) }
}
public struct AppAssociatedFile:Identifiable,Sendable {
    public var id:String { item.id }
    public let item:ReviewItem;public let kind:AppFileKind;public let blockedReason:String?
    public init(item:ReviewItem,kind:AppFileKind,blockedReason:String?=nil) { self.item=item;self.kind=kind;self.blockedReason=blockedReason }
    public var selectable:Bool { blockedReason == nil && item.measurement.complete }
}
public struct AppAssociationReport:Sendable {
    public let appID:String;public let files:[AppAssociatedFile];public let issues:[String];public let date:Date
    public init(appID:String,files:[AppAssociatedFile],issues:[String]=[],date:Date=Date()) { self.appID=appID;self.files=files;self.issues=issues;self.date=date }
}
public struct AppRemovalPlan:Sendable {
    public let report:AppAssociationReport;public private(set) var selected:Set<String>
    public init(report:AppAssociationReport,selectDefaults:Bool=false,retaining:Set<String>?=nil) {
        self.report=report
        let eligible=Set(report.files.filter(\.selectable).map(\.id))
        selected=retaining.map { $0.intersection(eligible) } ?? (selectDefaults ? Set(report.files.filter { $0.selectable && $0.kind.ready }.map(\.id)) : [])
    }
    public mutating func set(_ id:String,selected:Bool) {
        guard report.files.contains(where:{$0.id==id && $0.selectable}) else { return }
        if selected { self.selected.insert(id) } else { self.selected.remove(id) }
    }
    public mutating func setReviewGroup(_ selected:Bool) {
        for file in report.files where !file.kind.ready && file.selectable { set(file.id,selected:selected) }
    }
    public mutating func clear() { selected=[] }
    public var items:[ReviewItem] { report.files.filter { selected.contains($0.id) && $0.selectable }.map(\.item) }
    /// Checked eligible paths, plus unchecked personal-data candidates still needing review.
    /// Unavailable/partial paths never inflate either actionable total.
    public var removalBytes:UInt64 { items.reduce(0) { $0+$1.measurement.allocated } }
    public var reviewBytes:UInt64 { report.files.filter { !$0.kind.ready && $0.selectable && !selected.contains($0.id) }.reduce(0) { $0+$1.item.measurement.allocated } }
    public var appBytes:UInt64 { report.files.filter { $0.kind == .application && selected.contains($0.id) }.reduce(0) { $0+$1.item.measurement.allocated } }
    public var dataBytes:UInt64 { report.files.filter { $0.kind != .application && selected.contains($0.id) }.reduce(0) { $0+$1.item.measurement.allocated } }
}
