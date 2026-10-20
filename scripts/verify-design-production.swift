import Foundation
@main struct ProductionDesignChecks {
    @MainActor static func main() throws {
        let suite="BonsaiProductionStyleTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        var checks=0
        func check(_ value:Bool,_ title:String) {checks+=1;guard value else {fatalError("FAIL "+title)};print("PASS "+title)}
        defaults.set(try JSONEncoder().encode(["clean.tree":ElementDesign(scale:1.4)]),forKey:"bonsaiDesign.v1")
        let compiled=try JSONEncoder().encode(["clean.tree":ElementDesign(scale:0.9),"unknown":ElementDesign()])
        let store=DesignPreferences(defaults:defaults,designData:compiled)
        check(store.value("clean.tree").scale==0.9,"Production uses compiled design settings, not editor preferences")
        check(store.values["unknown"]==nil,"Production ignores unknown design targets")
        check(!store.active,"Production starts without an editing state")
        store.save()
        check(try JSONDecoder().decode([String:ElementDesign].self,from:defaults.data(forKey:"bonsaiDesign.v1")!)["clean.tree"]?.scale==1.4,"Production does not write editor preferences")
        let fresh=DesignPreferences(defaults:defaults,designData:Data("{}".utf8))
        check(fresh.value("clean.tree")==ElementDesign(),"Empty compiled styles preserve the approved interface")
        let invalid=try JSONEncoder().encode(["clean.tree":ElementDesign(scale:8,x:999)])
        let safe=DesignPreferences(defaults:defaults,designData:invalid)
        check(safe.value("clean.tree").scale==1.4 && safe.value("clean.tree").x==80,"Compiled styles are validated")
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("BonsaiStyleExport-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:temp)}
        let output=temp.appendingPathComponent("InterfaceDesign.json")
        try store.export(to:output)
        let reloaded=DesignPreferences(defaults:defaults,designData:try Data(contentsOf:output))
        check(reloaded.values==store.values,"Exported settings reproduce identical production styles")
        check(DesignPreferences(defaults:defaults,designData:Data("broken".utf8)).values.isEmpty,"Malformed compiled styles recover without using editor preferences")
        var failure=false
        do {try store.export(to:temp.appendingPathComponent("missing/InterfaceDesign.json"))} catch {failure=true}
        check(failure,"Failed exports report an error instead of claiming success")
        print("RESULT: \(checks) production style checks, zero failures")
    }
}
