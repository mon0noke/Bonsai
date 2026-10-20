import SwiftUI
import AppKit
import ServiceManagement
import BonsaiCore

struct SoftwareView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store:SoftwareStore
    @ObservedObject var updateStore:SoftwareUpdatesStore
    @ViewState private var ownLoginState=SMAppService.mainApp.status
    @ViewState var query=""
    @ViewState var searching=false
    @FocusState var searchFocused:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tab:String { model.softwareTab }
    var apps:[InstalledApp] { store.visible(model.apps,query:query,revision:model.inventoryRevision) }
    var body:some View {
        Group {
        if model.uninstallScreen != .list { SoftwareUninstallView() }
        else { VStack(alignment:.leading,spacing:18) {
            HStack(spacing:14) {
                SoftwareTabs(selection:$model.softwareTab).designElement("apps.tabs")
                Button { if tab=="Uninstall" { model.inventoryApps() } else if tab=="Startup" { model.loadStartup();if model.loginRead {model.readLoginItems()} } else { model.checkUpdates() } } label: { Image(systemName:"arrow.clockwise").font(.system(size:13)) }.handCursor().buttonStyle(.plain).foregroundStyle(Palette.muted).help("Refresh "+tab).accessibilityLabel("Refresh "+tab).disabled(model.busy)
                Spacer(minLength:12)
                if (tab=="Uninstall" || tab=="Updates") && !searching {
                    ForEach(AppSortField.allCases,id:\.self) { field in
                        Button { store.chooseSort(field) } label: { Text(field.title+(store.sort.field==field ? (store.sort.ascending ? " ↑" : " ↓") : "")).padding(.horizontal,7).padding(.vertical,7).contentShape(Rectangle()) }.buttonStyle(.plain).handCursor().font(.system(size:11,weight:store.sort.field==field ? .bold : .regular)).foregroundStyle(store.sort.field==field ? Palette.text : Palette.muted).accessibilityLabel("Sort by "+field.title).accessibilityValue(store.sort.field==field ? (store.sort.ascending ? "Ascending" : "Descending") : "Not selected").accessibilityAddTraits(store.sort.field==field ? .isSelected : []).help(field == .installed ? "Application folder creation date, not a verified installation history. Click again to reverse." : "Click again to reverse the selected sort. Unknown values stay last.")
                    }
                    Menu { Toggle("Include system applications",isOn:$store.includeSystem) } label: { Image(systemName:"line.3.horizontal.decrease").frame(width:24,height:28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).handCursor().accessibilityLabel("Application filters")
                }
                if searching {
                    HStack(spacing:8) {
                        Image(systemName:"magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("Search "+tab,text:$query).textFieldStyle(.plain).focused($searchFocused).task {searchFocused=false;await Task.yield();searchFocused=true}
                        Button {query="";searching=false;searchFocused=false} label:{Image(systemName:"xmark").font(.system(size:10,weight:.semibold))}.handCursor().buttonStyle(.plain).accessibilityLabel("Close search")
                    }.font(.system(size:12)).padding(.horizontal,12).padding(.vertical,9).frame(width:220).background(Palette.card,in:Capsule()).transition(.opacity)
                }
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration:0.2)) {searching.toggle();if !searching {query=""};if !searching {searchFocused=false}} } label:{Image(systemName:"magnifyingglass").font(.system(size:14))}.handCursor().buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Search "+tab).keyboardShortcut("f",modifiers:.command)
            }.padding(.bottom,4)
            BonsaiScrollView { ZStack(alignment:.topLeading) {
                Group {
                    if tab=="Uninstall" { uninstallContent }
                    else if tab=="Updates" { updatesContent }
                    else { startupContent }
                }
            }.padding(.bottom,8) }.frame(maxWidth:.infinity,maxHeight:.infinity).bonsaiListSurface(radius:14)
            if tab=="Uninstall",!store.chosen.isEmpty { selectionFooter }
        } }
        }.animation(reduceMotion ? nil : .easeOut(duration:0.24),value:model.uninstallScreen)
        .task { if tab=="Updates" {updateStore.enter(apps:model.apps)};if tab=="Startup" {model.loadStartup()};if model.apps.isEmpty && !model.busy && !model.inventoryBusy && model.uninstallScreen == .list { model.inventoryApps() } }
        .onChange(of:model.apps.map {$0.bundleID+"|"+$0.version+"|"+$0.id}) {_,_ in if tab=="Updates" {updateStore.enter(apps:model.apps)}}
        .onChange(of:tab) { _,value in query="";if value=="Updates" {updateStore.enter(apps:model.apps)};if value=="Startup" {model.loadStartup()} }

    }
    var uninstallContent:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) { NatureIllustration(scene:.elm).frame(width:44,height:44).designElement("apps.tree").accessibilityLabel(NatureScene.elm.name);Text("Installed Apps").font(.system(size:12,weight:.semibold)).designElement("apps.title");Text("\(apps.count) app\(apps.count==1 ? "" : "s") · "+bytes(apps.reduce(0) { $0+$1.measurement.allocated })+(apps.contains(where:{!$0.measurement.complete || $0.measurement.files==0}) ? " measured":"")).secondaryText().help(model.inventoryNote).designElement("apps.caption");Spacer();if model.uninstallDate != nil {Button("Last removal") {model.uninstallScreen = .details}.buttonStyle(QuietTextStyle()).handCursor()};Button("Add app…",action:model.addApp).buttonStyle(QuietTextStyle()).handCursor().disabled(model.busy).designElement("apps.action") }
            if !model.apps.isEmpty && apps.isEmpty { EmptyState(symbol:"magnifyingglass",title:"No matching applications",detail:"Change the search, include system apps in Filters, or add an application from another folder.") }
            if model.apps.isEmpty {if model.inventoryBusy {Color.clear.frame(height:4)} else {EmptyState(symbol:"app.dashed",title:"No applications listed",detail:"Refresh to inspect supported application folders.")}}
            if model.inventoryBusy {
                SoftwareRefreshStatus(title:model.inventoryProgress,cancel:model.cancelInventory)
            }
            LazyVStack(spacing:8) { ForEach(apps) { app in AppUninstallRow(store:store,app:app,alternate:false) } }
        }
    }
    var selectionFooter:some View {
        let items=store.selectedItems
        let selectedApps=model.apps.filter {store.chosen.contains($0.id)}
        let running=items.contains {ApplicationActivity.isRunning($0.runningIDs,among:model.runningAppIDs)}
        return HStack(spacing:14) {
            HStack(spacing:-9) {ForEach(Array(selectedApps.prefix(3))) {app in Image(nsImage:store.icon(app)).resizable().frame(width:30,height:30).accessibilityHidden(true)}}
            VStack(alignment:.leading,spacing:5) {
                Text(store.inspectionsPending ? "Inspecting selected files…" : "\(selectedApps.count==1 ? selectedApps[0].name : "\(selectedApps.count) apps") · "+bytes(store.selectedBytes)).font(.system(size:13,weight:.semibold))
                Text(running ? "Quit selected apps before removal." : "\(items.count) checked paths · recoverable from Trash").font(.system(size:10)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:12)
            Button("Clear selection") {store.clear()}.buttonStyle(QuietTextStyle()).handCursor().disabled(model.busy)
            Button {model.removeSoftwareSelection(expected:Set(items.map(\.id)))} label:{Text("Uninstall \(selectedApps.count)").frame(width:140,height:34)}
                .buttonStyle(UninstallButtonStyle()).handCursor().disabled(model.busy || store.inspectionsPending || items.isEmpty || running)
                .accessibilityHint("Move the checked paths to Trash and show a report.")
        }.padding(.horizontal,16).padding(.vertical,14).bonsaiGlass(radius:20)
    }
    var updatesContent:some View {SoftwareUpdatesPanel(updates:updateStore,software:store,query:query)}
    var startupContent:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("Login items").font(.system(size:12,weight:.semibold));if model.loginRead {Text("\(model.loginEntries.filter {$0.section=="Login items"}.count)").secondaryText()};Spacer()
                if !model.loginRead {Button("Read login items") {model.readLoginItems()}.handCursor().buttonStyle(QuietTextStyle()).disabled(model.busy)}
            }
            HStack(spacing:14) {
                Image(nsImage:NSWorkspace.shared.icon(forFile:Bundle.main.bundlePath)).resizable().frame(width:34,height:34).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5) {Text("Bonsai").font(.system(size:13,weight:.semibold));Text("App").secondaryText().help(ownLoginDescription)};Spacer()
                Toggle("Open Bonsai at login",isOn:Binding(get:{ownLoginState == .enabled},set:{enabled in
                    do {if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()};ownLoginState=SMAppService.mainApp.status
                        if ownLoginState == .requiresApproval {model.loginSettings()}
                    } catch {ownLoginState=SMAppService.mainApp.status;model.error=error.localizedDescription}
                })).labelsHidden().toggleStyle(BonsaiSwitchStyle()).controlSize(.small).tint(Palette.sage).handCursor().accessibilityLabel("Open Bonsai at login").disabled(model.busy)
            }.padding(.horizontal,16).padding(.vertical,14)
            ForEach(["Login items","Allow in the background"],id:\.self) {section in
                let items=model.loginEntries.filter {$0.identifier != Bundle.main.bundleIdentifier && $0.section==section && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))}
                if !items.isEmpty {
                    if section != "Login items" {Text(section+" · \(items.count)").font(.system(size:12,weight:.semibold))}
                    LazyVStack(spacing:0) {ForEach(items) {item in
                        loginRow(item)
                    }}
                }
            }

            HStack {Text("Background services").font(.system(size:12,weight:.semibold));Text("\(model.startup.count+managedServices.count)").secondaryText();Spacer()}
            if model.startupLoading {SoftwareRefreshStatus(title:"Reading background services")} else if model.startup.isEmpty && managedServices.isEmpty {EmptyState(symbol:"gearshape.2",title:"No services listed",detail:"Refresh to inspect launch agents.")}
            if !model.startupNote.isEmpty {Text(model.startupNote).secondaryText()}
            LazyVStack(spacing:0) {ForEach(managedServices.filter {query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)}) {loginRow($0)}}
            LazyVStack(spacing:0) {ForEach(model.startup.filter {query.isEmpty || $0.label.localizedCaseInsensitiveContains(query)}) {item in
                HStack(spacing:14) {
                    if let appURL=item.applicationURL {Image(nsImage:NSWorkspace.shared.icon(forFile:appURL.path)).resizable().frame(width:34,height:34).accessibilityHidden(true)} else {Image(systemName:item.isProtected ? "lock.shield" : "gearshape.2").font(.system(size:24,weight:.light)).foregroundStyle(Palette.muted).frame(width:34)}
                    VStack(alignment:.leading,spacing:6) {
                        Text(startupName(item)).font(.system(size:13,weight:.semibold));Text("App").secondaryText().help(item.source+" · "+item.state)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if let disabled=item.disabled {
                        Toggle(item.label,isOn:Binding(get:{!disabled},set:{_ in if item.controllable {model.changeStartup(item)} else {model.loginSettings()}})).labelsHidden().toggleStyle(BonsaiSwitchStyle()).controlSize(.small).tint(Palette.sage).handCursor().disabled(model.busy).accessibilityLabel(item.controllable ? "Enable "+item.label : "Manage "+item.label+" in System Settings").accessibilityHint(item.controllable ? "Change startup state" : "Opens System Settings. This service is not writable by Bonsai.")
                    } else {Button("Settings") {model.loginSettings()}.buttonStyle(QuietTextStyle()).handCursor()}
                }.padding(.horizontal,16).padding(.vertical,14)
            }}
        }.onAppear {ownLoginState=SMAppService.mainApp.status}.onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) {_ in ownLoginState=SMAppService.mainApp.status;model.loadStartup()}
    }
    var managedServices:[LoginEntry] {
        model.loginEntries.filter {entry in
            guard entry.section=="Background services" else {return false}
            return !model.startup.contains {native in
                guard native.label==entry.launchLabel else {return false}
                return entry.kind=="Launch agent" ? native.source.hasSuffix("LaunchAgent") : native.source.hasSuffix("LaunchDaemon")
            }
        }
    }
    func loginRow(_ item:LoginEntry)->some View {
        HStack(spacing:14) {
            if let url=item.url {Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:34,height:34).accessibilityHidden(true)} else {Image(systemName:"app").frame(width:34).foregroundStyle(Palette.muted)}
            VStack(alignment:.leading,spacing:6) {Text(item.name).font(.system(size:13,weight:.semibold));Text("App").secondaryText().help(item.kind+" · "+(model.loginNeedsRefresh ? "Saved state" : "Current state"))}.frame(maxWidth:.infinity,alignment:.leading)
            if let state=item.enabled {
                Toggle("Manage "+item.name+" in System Settings",isOn:Binding(get:{state},set:{_ in model.loginSettings()})).labelsHidden().toggleStyle(BonsaiSwitchStyle()).controlSize(.small).tint(Palette.sage).handCursor().accessibilityLabel("Manage "+item.name+" in System Settings").accessibilityHint("Manage this registration in Login Items")
            } else {Button("Settings") {model.loginSettings()}.handCursor().buttonStyle(QuietTextStyle())}
        }.padding(.horizontal,16).padding(.vertical,14)
            .bonsaiListHover().designElement("apps.startupRows")
            .contextMenu {if let url=item.url {Button("Reveal in Finder") {model.reveal(url)}};Button("System Settings") {model.loginSettings()}}
    }
    func startupName(_ item:StartupItem)->String {
        if let record=model.loginEntries.first(where:{$0.launchLabel==item.label}) {return record.name}
        if let url=item.applicationURL,let bundle=Bundle(url:url) {return bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String ?? item.label}
        return item.label
    }
    var ownLoginDescription:String {switch ownLoginState {case .enabled:return "Opens at login";case .notRegistered:return "Open at login is off";case .requiresApproval:return "Approval needed in Login Items";case .notFound:return Bundle.main.bundlePath.hasPrefix("/Applications/") ? "Not registered with macOS" : "Install in Applications to enable";@unknown default:return "State unavailable"}}

}
struct SourceBadge:View {
    var text:String
    var body:some View { Text(text).font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.muted).padding(.horizontal,5).padding(.vertical,3).background(Palette.text.opacity(0.05),in:RoundedRectangle(cornerRadius:4)) }
}
