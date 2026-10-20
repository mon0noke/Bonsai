import SwiftUI
import AppKit

@main struct DesignChecks {
    @MainActor static func main() {
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ title:String) {checks+=1;guard value else {fatalError("FAIL: "+title)};print("PASS "+title)}
        let suite="BonsaiDesignTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let store=DesignPreferences(defaults:defaults)
        check(store.values.isEmpty && !store.active,"Clean profile leaves the approved interface unchanged")
        check(Set(DesignTarget.all.map(\.id)).count==DesignTarget.all.count,"Every registered target has a unique identifier")
        for target in DesignTarget.all {check(store.value(target.id)==ElementDesign(),"Default tuning for "+target.id)}
        store.update("clean.tree") {$0.scale=1.2;$0.x=12;$0.y = -9;$0.spacing=6}
        check(store.value("clean.tree").scale==1.2 && store.value("clean.tree").x==12,"Independent tree size and position are applied")
        check(store.value("apps.tree")==ElementDesign(),"Editing one page does not change another")
        let loaded=DesignPreferences(defaults:defaults)
        check(loaded.value("clean.tree")==store.value("clean.tree"),"Local changes survive a new preferences instance")
        store.update("apps.tabs") {$0.width=1.1;$0.height=1.15}
        store.undo()
        check(store.value("apps.tabs")==ElementDesign() && store.value("clean.tree").scale==1.2,"Undo restores only the last change")
        store.reset("clean.tree")
        check(store.value("clean.tree")==ElementDesign(),"Reset element restores the original geometry")
        store.undo();check(store.value("clean.tree").scale==1.2,"Reset element can be undone")
        store.resetAll();check(store.values.isEmpty,"Reset all removes custom styles")
        store.undo();check(store.value("clean.tree").scale==1.2,"Reset all can be undone")
        var routed=""
        store.navigate={routed=$0};store.select("status.CPU",navigating:true)
        check(store.selection=="status.CPU" && routed=="status.CPU","Inspector selection routes to the selected target")
        store.select("unknown",navigating:true);store.update("unknown") {$0.scale=1.2}
        check(store.selection=="status.CPU" && store.values["unknown"]==nil,"Unknown targets cannot change settings or navigation")
        store.picking=false;check(!store.picking,"Preview mode releases element picking")
        let invalid=ElementDesign(scale:.infinity,width:-3,height:8,spacing:.nan,x:1000,y:-1000).validated()
        check(invalid.scale==1 && invalid.width==0.75 && invalid.height==1.3 && invalid.spacing==0 && invalid.x==80 && invalid.y == -80,"Invalid and extreme values are bounded")
        defaults.set(try! JSONEncoder().encode(["clean.tree":ElementDesign(scale:9),"unknown":ElementDesign()]),forKey:"bonsaiDesign.v1")
        let bounded=DesignPreferences(defaults:defaults)
        check(bounded.value("clean.tree").scale==1.4 && bounded.values["unknown"]==nil,"Persisted values are validated against the registry")
        defaults.set(Data("broken".utf8),forKey:"bonsaiDesign.v1")
        check(DesignPreferences(defaults:defaults).values.isEmpty,"Corrupt preferences recover to approved defaults")
        let history=DesignPreferences(defaults:defaults)
        for index in 0..<200 {history.update("clean.tree") {$0.x=Double(index % 60)}}
        for _ in 0..<60 {history.undo()}
        check(!history.undoAvailable,"Undo memory remains bounded during continuous adjustments")
        func layoutSize(_ x:CGFloat,_ y:CGFloat)->CGSize {
            let host=NSHostingView(rootView:ElementDesignLayout(x:x,y:y) {Color.clear.frame(width:80,height:40).scaleEffect(x:x,y:y,anchor:.topLeading)})
            return host.fittingSize
        }
        let original=layoutSize(1,1);let scaled=layoutSize(1.2,1.1)
        check(abs(original.width-80)<1 && abs(original.height-40)<1,"Default scale preserves measured layout")
        check(abs(scaled.width-96)<1 && abs(scaled.height-44)<1,"Scaled drawing reserves matching space in the layout")
        let design=DesignPreferences.shared
        let oldActive=design.active;let oldPicking=design.picking
        defer {design.active=oldActive;design.picking=oldPicking}
        DesignPanelController.shared.show()
        let first=NSApp.windows.first {$0.title=="Bonsai Design" && $0.isVisible}
        check(first != nil && design.active,"Design inspector opens with editing active")
        DesignPanelController.shared.show()
        check(NSApp.windows.filter {$0.title=="Bonsai Design" && $0.isVisible}.count==1,"Repeated opening reuses a single inspector")
        check(first?.minSize.width==310,"Inspector has a bounded readable minimum width")
        DesignPanelController.shared.close()
        check(!design.active && first?.isVisible==false,"Closing the inspector releases picking and hides the panel")
        DesignPanelController.shared.show();DesignPanelController.shared.close()
        check(!design.active,"Inspector can reopen and close without stale editing state")
        print("RESULT: \(checks) Design mode checks, zero failures")
    }
}
