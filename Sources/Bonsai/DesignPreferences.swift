import Foundation
import Combine

struct DesignTarget:Identifiable,Hashable {
    enum Kind {case element,text,tree,navigation,spacing}
    let id:String;let title:String;let section:String;let kind:Kind
    static let all:[DesignTarget] = {
        var targets=[DesignTarget(id:"navigation.spacing",title:"Navigation spacing",section:"Navigation",kind:.spacing)]
        for title in ["Clean","Apps","Optimize","Analyze","Status"] {targets.append(.init(id:"navigation."+title,title:title+" navigation button",section:"Navigation",kind:.navigation))}
        for (section,prefix) in [("Clean","clean"),("Apps","apps"),("Optimize","optimize"),("Analyze","analyze")] {
            targets += [.init(id:prefix+".tree",title:section+" tree",section:section,kind:.tree),.init(id:prefix+".caption",title:section+" tree caption",section:section,kind:.text),.init(id:prefix+".title",title:section+" heading / verse",section:section,kind:.text),.init(id:prefix+".action",title:section+" main action",section:section,kind:.element)]
        }
        targets += [.init(id:"analyze.sidebarTree",title:"Disk explorer tree",section:"Analyze",kind:.tree),.init(id:"analyze.choose",title:"Choose folder button",section:"Analyze",kind:.element),.init(id:"analyze.rows",title:"Folder list rows",section:"Analyze",kind:.element),.init(id:"apps.tabs",title:"Apps tab buttons",section:"Apps",kind:.element),.init(id:"apps.uninstallRows",title:"Uninstall list rows",section:"Apps",kind:.element),.init(id:"apps.updateRows",title:"Update list rows",section:"Apps",kind:.element),.init(id:"apps.startupRows",title:"Startup list rows",section:"Apps",kind:.element),.init(id:"clean.rows",title:"Cleanup category rows",section:"Clean",kind:.element),.init(id:"settings.tabs",title:"Settings tab buttons",section:"Settings",kind:.element),.init(id:"settings.rows",title:"Settings rows",section:"Settings",kind:.element),.init(id:"settings.title",title:"Settings title",section:"Settings",kind:.text),.init(id:"status.rows",title:"Process list rows",section:"Status",kind:.element),.init(id:"status.tree",title:"Status olive tree",section:"Status",kind:.tree)]
        for title in ["HEALTH","CPU","GPU","MEMORY","BATTERY","DISK","NETWORK","THERMAL"] {targets.append(.init(id:"status."+title,title:title.capitalized+" card",section:"Status",kind:.element))}
        return targets
    }()
    static func find(_ id:String)->DesignTarget? {all.first {$0.id==id}}
}
struct ElementDesign:Codable,Equatable {
    var scale:Double=1
    var width:Double=1
    var height:Double=1
    var spacing:Double=0
    var x:Double=0
    var y:Double=0
    func validated()->Self {
        func clamp(_ value:Double,_ limits:ClosedRange<Double>,_ fallback:Double)->Double {value.isFinite ? min(limits.upperBound,max(limits.lowerBound,value)):fallback}
        return .init(scale:clamp(scale,0.65...1.4,1),width:clamp(width,0.75...1.3,1),height:clamp(height,0.75...1.3,1),spacing:clamp(spacing,0...18,0),x:clamp(x,-80...80,0),y:clamp(y,-80...80,0))
    }
}
@MainActor final class DesignPreferences:ObservableObject {
    static let shared=DesignPreferences()
    @Published private(set) var values:[String:ElementDesign]=[:]
    @Published var active=false
    @Published var picking=true
    @Published var selection="clean.tree"
    @Published private(set) var undoAvailable=false
    var navigate:((String)->Void)?
    private var history:[[String:ElementDesign]]=[]
    private let defaults:UserDefaults
    private let storageKey="bonsaiDesign.v1"
    init(defaults:UserDefaults = .standard,designData:Data?=nil,restoreSession:Bool=true) {
        self.defaults=defaults
        let data=designData ?? Bundle.main.url(forResource:"InterfaceDesign",withExtension:"json").flatMap {try? Data(contentsOf:$0)}
        if let data,let decoded=try? JSONDecoder().decode([String:ElementDesign].self,from:data) {values=decoded.filter {DesignTarget.find($0.key) != nil}.mapValues {$0.validated()}}
        #if BONSAI_DESIGN_EDITOR
        if restoreSession,let data=defaults.data(forKey:storageKey),let decoded=try? JSONDecoder().decode([String:ElementDesign].self,from:data) {
            values=decoded.filter {DesignTarget.find($0.key) != nil}.mapValues {$0.validated()}
        }
        #endif
    }
    func export(to url:URL) throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(values).write(to:url,options:.atomic)
    }
    func value(_ id:String)->ElementDesign {values[id] ?? ElementDesign()}
    func select(_ id:String,navigating:Bool=false) {guard let target=DesignTarget.find(id) else {return};selection=id;if navigating {navigate?(target.id)}}
    func update(_ id:String,_ change:(inout ElementDesign)->Void) {
        guard DesignTarget.find(id) != nil else {return}
        var next=value(id);change(&next);next=next.validated()
        guard next != value(id) else {return};remember();values[id]=next;save()
    }
    func reset(_ id:String) {guard values[id] != nil else {return};remember();values.removeValue(forKey:id);save()}
    func resetAll() {guard !values.isEmpty else {return};remember();values=[:];save()}
    func undo() {guard let old=history.popLast() else {return};values=old;undoAvailable = !history.isEmpty;save()}
    private func remember() {history.append(values);if history.count>60 {history.removeFirst()};undoAvailable=true}
    func save() {
        #if BONSAI_DESIGN_EDITOR
        if let data=try? JSONEncoder().encode(values) {defaults.set(data,forKey:storageKey)}
        #endif
    }
}
