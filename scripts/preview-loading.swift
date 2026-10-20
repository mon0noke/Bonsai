import SwiftUI
import AppKit
import BonsaiCore

/// Read-only visual fixture. Built separately; never included in Bonsai.app.
@main struct LoadingPreview:App {
    @NSApplicationDelegateAdaptor(StudioDelegate.self) var delegate
    @StateObject private var model=AppModel(startServices:false)
    @StateObject private var demoUpdates=SoftwareUpdatesStore(defaults:nil,check:{apps,progress in
        let report=MetadataCheckReport(updates:apps.map {SoftwareUpdate(id:"fixture:"+$0.id,name:$0.name,installed:$0.version,available:"2.0",source:"Appcast",information:"Display-only QA source",applicationURL:$0.url)},notes:["Display-only fixture: no network requests"],checked:apps.count)
        await progress(report);return report
    })
    @ViewState private var selection="Clean landing"
    @ViewState private var dark=true
    @ViewState private var reduced=false
    @ViewState private var small=false
    let cases=["Clean landing","Clean review","Clean scan","Clean rescan","Analyze scan","Optimize run","Uninstall run","Activity details","Apps refresh","Updates demo","Analyze idle","Analyze map","Background mapping","Optimize details","Optimize complete","Settings","Status demo"]
    var body:some Scene {
        Window("Bonsai Design Studio",id:"qa") {
            VStack(spacing:0) {
                HStack(spacing:12) {
                    Button("Previous") {move(-1)};Text(selection).frame(width:120);Button("Next") {move(1)}
                    Menu("Scenes") {ForEach(cases,id:\.self) {name in Button(name) {selection=name}}}
                    if selection=="Clean scan" || selection=="Clean rescan" {Button("Finish scan") {selection="Clean review"}}
                    if selection=="Clean review" {Button("Restart scan") {selection="Clean scan"}}
                    Toggle("Dark",isOn:$dark);Toggle("Still motion",isOn:$reduced)
                    Button(small ? "Regular window" : "Smallest window") {small.toggle();NSApp.windows.first(where:{$0.title=="Bonsai Design Studio"})?.setContentSize(NSSize(width:small ? 980 : 1186,height:small ? 740 : 812))}
                    Button("Edit layout") {DesignPanelController.shared.show()};Spacer();Text("Developer preview").font(.caption);Button("Quit preview") {NSApp.terminate(nil)}
                }.padding(12).background(.regularMaterial)
                Group {
                    if selection=="Activity details" {
                        VStack(spacing:20) {
                            Text("Background activity").font(.title2)
                            BonsaiActivityStrip(title:"Checking update sources",detail:"Available updates appear as each source finishes",cancelTitle:"Stop",cancel:{})
                            BonsaiActivityStrip(title:"Reading background services",detail:"Checking persistent and current-session state")
                            BonsaiActivityStrip(title:"Inspecting application files",detail:"Measuring associated data",cancel:{})
                            BonsaiActivityStrip(title:"Reading process details",detail:"Checking this process identity")
                        }.frame(maxWidth:630).padding(30).frame(maxWidth:.infinity,maxHeight:.infinity).background(BonsaiBackground(page:.software)).foregroundStyle(Palette.text)
                    } else if selection=="Updates demo" {
                        VStack {
                            HStack {ForEach(AppSortField.allCases,id:\.self) {field in Button(field.title+(model.software.sort.field==field ? (model.software.sort.ascending ? " ↑":" ↓"):"")) {model.software.chooseSort(field)}};Spacer()}.padding(.horizontal,24)
                            ScrollView {SoftwareUpdatesPanel(updates:demoUpdates,software:model.software,query:"").padding(24)}.developerDesignSurface()
                        }.environmentObject(model).background(BonsaiBackground(page:.software)).foregroundStyle(Palette.text).task {demoUpdates.enter(apps:model.apps)}
                    } else {RootView().environmentObject(model).compactInterface().developerDesignSurface()}
                }.environment(\.bonsaiMotionSuppressed,reduced)
            }.preferredColorScheme(dark ? .dark : .light)
                .onAppear {UserDefaults.standard.set("system",forKey:"appearance");configure()}
                .onChange(of:selection) {_,_ in configure()}
        }.defaultSize(width:1186,height:812).windowStyle(.hiddenTitleBar)
    }
    func move(_ step:Int) {let index=cases.firstIndex(of:selection) ?? 0;selection=cases[(index+step+cases.count)%cases.count]}
    func demoApps()->[InstalledApp] {
        ["Fern","Willow","Juniper"].enumerated().map {index,name in
            var measurement=Measurement();measurement.allocated=UInt64(index+1)*12_000_000;measurement.files=index==2 ? 0:1
            return InstalledApp(url:URL(fileURLWithPath:"/Bonsai-display-only/"+name+".app"),name:name,bundleID:"app.bonsai.fixture."+name,version:"1.0",measurement:measurement,lastUsed:index==2 ? nil:Date(timeIntervalSince1970:Double(index+1)*10000),appStore:false,installedDate:index==2 ? nil:Date(timeIntervalSince1970:Double(index+1)*10000))
        }
    }
    @MainActor func configure() {
        DesignPreferences.shared.navigate?("clean.tree")
        model.diskScanning=false;model.diskProgress="";model.inventoryBusy=false;model.busy=true;model.lastScan=nil;model.cleanItems=[];model.selected=[];model.disk=nil;model.diskIncremental=[];model.maintenanceScreen = .overview;model.uninstallScreen = .list
        model.cleanScanAllocated=1_320_000_000
        model.progress="Application caches · 128 locations measured · ~/Library/Application Support/Example/data"
        switch selection {
        case "Settings":model.busy=false;model.page = .clean;model.requestedUtility="settings"
        case "Status demo":
            model.busy=false;model.page = .status;model.snapshot=TelemetrySnapshot();model.snapshot.memoryTotal=16_000_000_000;model.snapshot.diskTotal=245_000_000_000;model.snapshot.diskFree=80_000_000_000;model.snapshot.pressure="Warning";model.snapshot.thermal="Nominal";model.snapshot.date=Date();model.snapshot.processes=(0..<30).map {ProcessSample(pid:Int32(5000+$0),uid:getuid(),start:1,startMicro:0,name:"Process \($0+1)",memory:UInt64(30-$0)*10_000_000,cpu:Double($0),cpuNS:0)};model.snapshot.processGroups=ProcessGrouping.groups(model.snapshot.processes,applications:[])
        case "Optimize complete":model.busy=false;model.page = .optimize;model.maintenanceScreen = .complete;model.maintenanceTasks=MaintenanceTask.catalog.filter {$0.recommended};model.maintenanceOutcomes=model.maintenanceTasks.map {ItemOutcome(title:$0.title,path:$0.preview,status:"Completed",detail:"Read-only visual fixture")};model.maintenanceDate=Date()
        case "Optimize details":
            model.busy=false;model.page = .optimize;model.maintenanceScreen = .details;model.maintenanceTasks=MaintenanceTask.catalog
            model.maintenanceOutcomes=model.maintenanceTasks.enumerated().map {index,task in ItemOutcome(title:task.title,path:task.preview,status:index%6==0 ? "Skipped":"Completed",detail:"Read-only display fixture. No maintenance command was executed.")};model.maintenanceDate=Date()
        case "Clean landing":model.page = .clean;model.operationKind="";model.busy=false
        case "Clean review":
            model.page = .clean;model.operationKind="";model.busy=false
            // Display-only sizes; nonexistent candidates have no manifest and cannot be removed.
            let names=["Application caches","Logs","Temporary files","Developer artifacts","AI tools","Browsers","Old installers"]
            let items=names.enumerated().compactMap {index,name->ReviewItem? in
                var measurement=Measurement();measurement.allocated=UInt64(index+1)*123_000_000;measurement.logical=measurement.allocated
                return try? ReviewItem(url:FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-layout-only-\(index)"),title:name,category:name,explanation:"Read-only visual fixture",risk:index<2 ? "Review":"High",measurement:measurement)
            }
            model.storeReport(CleanReport(items:items,issues:["Display-only partial report"],completeWithinCatalog:false,deniedDiscoveryPaths:["/Bonsai-layout-only"]),mode:.caches)
        case "Clean rescan":model.page = .clean;model.operationKind="clean";model.lastScan=Date()
        case "Analyze scan":model.page = .analyze;model.busy=false;model.operationKind="";model.diskScanning=true;model.diskProgress="Library · 42,180 items checked"
        case "Optimize run":model.page = .optimize;model.operationKind="maintenance";model.maintenanceScreen = .run;model.maintenanceTasks=MaintenanceTask.catalog.filter {$0.recommended};model.maintenanceActive=model.maintenanceTasks.first?.id;model.progress="Refreshing Finder previews"
        case "Apps refresh":model.page = .software;model.softwareTab="Uninstall";model.busy=false;model.inventoryBusy=true;model.inventoryProgress="Refreshing application sizes · 1 / 2";model.apps=demoApps()
        case "Updates demo":model.page = .software;model.softwareTab="Updates";model.busy=false;model.apps=demoApps()
        case "Analyze map":
            model.page = .analyze;model.operationKind="";model.busy=false
            let root=URL(fileURLWithPath:"/Bonsai-display-only")
            model.diskRoot=root;model.diskOverview=false
            model.diskIncremental=(["Documents","Downloads","Library",".hidden-cache"]+(0..<25).map {"Folder \($0)"}).enumerated().map {index,name in var m=Measurement();m.allocated=index==0 ? 9_000_000_000:UInt64(index+1)*24_000_000;m.logical=m.allocated;m.files=1;return DiskEntry(url:root.appendingPathComponent(name),directory:true,measurement:m)}
        case "Background mapping":model.page = .optimize;model.operationKind="";model.busy=false;model.diskScanning=true;model.diskProgress="Library · 42,180 items checked"
        case "Analyze idle":model.page = .analyze;model.operationKind="";model.busy=false
        case "Uninstall run":model.page = .software;model.operationKind="uninstall";model.uninstallScreen = .run;model.progress="Revalidating selected files";model.uninstallCurrent="~/Library/Application Support/Disposable Fixture/cache"
        default:model.page = .clean;model.operationKind="clean"
        }
    }
}

final class StudioDelegate:NSObject,NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationDidFinishLaunching(_ notification:Notification) {NSApp.setActivationPolicy(.regular)}
}
