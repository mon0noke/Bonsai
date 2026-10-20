import SwiftUI
import AppKit
import BonsaiCore

struct AppUninstallRow:View {
    @EnvironmentObject private var model:AppModel
    @ObservedObject var store:SoftwareStore
    let app:InstalledApp;let alternate:Bool
    @ViewState private var hovered=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var plan:AppRemovalPlan? { store.plans[app.id] }
    private var expanded:Bool { store.expanded.contains(app.id) }
    private var chosen:Bool { store.chosen.contains(app.id) }
    private var running:Bool { ApplicationActivity.isRunning([app.bundleID],among:model.runningAppIDs) }
    private var activityHint:String {
        var labels:[String]=[]
        if app.isMenuBarApp {labels.append("Menu bar app")}
        if running {labels.append("active now")}
        else if let date=app.lastUsed,app.lastUsedSource != "Filesystem access" {labels.append((app.lastUsedSource=="Spotlight last used" ? "opened " : "active ")+date.formatted(.relative(presentation:.numeric)))}
        return labels.isEmpty ? "" : labels.joined(separator:", ")+". "
    }
    private var selectionHint:String { activityHint+"Version \(app.version), \(app.measurement.label)\(running ? ", running now" : ""). "+(chosen ? "Click to expand or collapse files. Use the checkbox on the right to deselect." : "Click to select this app. Click again to inspect its files.") }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:14) {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration:0.24)) { store.activateApp(app,inventory:model.apps,policy:model.softwarePolicy) }
                } label: {
                    HStack(spacing:14) {
                        Image(nsImage:store.icon(app)).resizable().frame(width:40,height:40).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:6) {
                            HStack(spacing:8) { Text(app.name).font(.system(size:14,weight:.semibold));if app.appStore { SourceBadge(text:"App Store") };if within(app.id,"/System") { SourceBadge(text:"System") } }
                            HStack(spacing:7) {
                                Text(app.version+" · "+(app.measurement.files>0 ? app.measurement.label : (model.inventoryBusy ? "Measuring…" : "Size unavailable"))).foregroundStyle(Palette.muted)
                                AppActivityLabels(app:app)
                            }.font(.system(size:11,weight:.medium,design:.monospaced)).lineLimit(1)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).handCursor().accessibilityLabel((chosen ? (expanded ? "Collapse files for " : "Expand files for ") : "Select ")+app.name).accessibilityValue(chosen ? "Selected, "+(expanded ? "Expanded" : "Collapsed") : "Not selected").accessibilityHint(selectionHint).disabled(model.busy)
                if chosen { disclosureButton }
                BonsaiActionMenu(label:"App actions for "+app.name,actions:appActions)
                Toggle("Select application group "+app.name,isOn:Binding(get:{chosen},set:{_ in store.toggleApp(app,inventory:model.apps,policy:model.softwarePolicy)})).toggleStyle(.checkbox).labelsHidden().handCursor().disabled(model.busy)
            }.padding(.horizontal,16).padding(.vertical,15)
            if chosen && expanded { details.padding(.horizontal,16).padding(.bottom,18).transition(.opacity) }
        }
        .background(Palette.sage.opacity(hovered ? 0.085 : 0),in:RoundedRectangle(cornerRadius:14))
        .overlay(RoundedRectangle(cornerRadius:14).stroke(Palette.sage.opacity(hovered ? 0.24 : 0),lineWidth:1).allowsHitTesting(false))
        .onHover { value in withAnimation(reduceMotion ? nil : .easeOut(duration:0.14)) { hovered=value && !model.busy } }
        .onDisappear { hovered=false }
        .onChange(of:model.busy) { _,busy in if busy { hovered=false } }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in hovered=false }
        .bonsaiContextMenu(actions:appActions).accessibilityElement(children:.contain).designElement("apps.uninstallRows")
    }
    private var appActions:[BonsaiMenuAction] {[
        .init("Open App","arrow.up.forward.app",perform:{model.open(app.url)}),
        .init("Reveal in Finder","folder",perform:{model.reveal(app.url)}),
        .init("Copy Path","doc.on.doc",group:1,perform:{bonsaiCopy(app.url.path)}),
        .init("Copy Bundle ID","number",group:1,enabled:!app.bundleID.isEmpty,perform:{bonsaiCopy(app.bundleID)}),
        .init("Inspect Files","list.bullet.rectangle",group:2,enabled:!model.busy,perform:{
            if !chosen {store.toggleApp(app,inventory:model.apps,policy:model.softwarePolicy)}
            if !expanded {store.toggleExpanded(app,inventory:model.apps,policy:model.softwarePolicy)}
        }),
        .init(chosen ? "Deselect App":"Select for Removal",chosen ? "minus.circle":"checkmark.circle",group:2,enabled:!model.busy,perform:{store.toggleApp(app,inventory:model.apps,policy:model.softwarePolicy)})
    ]}
    private var summary:String {
        if let plan { return summarySize(plan.removalBytes)+" to remove · "+summarySize(plan.reviewBytes)+" to review" }
        switch store.details[app.id] { case .queued?,.loading?:return "Inspecting…";case .failed?:return "Inspection unavailable";default:return "Inspect files" }
    }
    private func summarySize(_ value:UInt64)->String { value==0 ? "0 MB" : bytes(value) }
    private var disclosureButton:some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration:0.24)) { store.toggleExpanded(app,inventory:model.apps,policy:model.softwarePolicy) }
        } label: {
            HStack(spacing:10) {
                Text(summary).font(.system(size:11,weight:.medium,design:.monospaced)).lineLimit(1)
                Image(systemName:"chevron.down").font(.system(size:12,weight:.semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration:0.24),value:expanded)
            }.padding(.horizontal,8).padding(.vertical,10).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor().foregroundStyle(hovered ? Palette.text : Palette.muted)
        .accessibilityLabel((expanded ? "Collapse files for " : "Inspect files for ")+app.name)
        .accessibilityValue(summary+", "+(expanded ? "Expanded" : "Collapsed"))
        .help("Click the entire summary to expand or collapse. Removal is the checked eligible paths; review is unchecked personal-data candidates. Unavailable paths are excluded. Sizes use allocated bytes.")
        .disabled(model.busy)
    }
    @ViewBuilder private var details:some View {
        switch store.details[app.id] {
        case .queued?,.loading?:
            BonsaiActivityStrip(title:"Inspecting application files",detail:"Measuring associated data",cancel:{store.cancelInspection(app.id)}).padding(.vertical,12)
        case .failed(let message)?:
            HStack { Text(message).secondaryText();Spacer();Button("Retry") { store.load(app,inventory:model.apps,policy:model.softwarePolicy,refresh:true) }.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy) }.padding(.vertical,12)
        default:
            if let plan {
                if running { Label("Quit this app before removing its files.",systemImage:"pause.circle").font(.system(size:11)).foregroundStyle(Palette.accent).padding(.bottom,12) }
                fileGroup("Ready to remove",files:plan.report.files.filter { $0.kind.ready && $0.selectable },review:false)
                fileGroup("Needs review",files:plan.report.files.filter { !$0.kind.ready && $0.selectable },review:true)
                fileGroup("Unavailable",files:plan.report.files.filter { !$0.selectable },review:false)
                ForEach(Array(plan.report.issues.enumerated()),id:\.offset) { _,issue in Text(issue).font(.system(size:11)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,6) }
                HStack { Text("Inspected "+plan.report.date.formatted(date:.omitted,time:.shortened)+" · sizes are allocated bytes").font(.system(size:10)).foregroundStyle(Palette.muted);Spacer();Button("Refresh files") { store.load(app,inventory:model.apps,policy:model.softwarePolicy,refresh:true) }.buttonStyle(QuietTextStyle()).handCursor().disabled(model.busy).help("Reinspect these paths. Existing selections are kept only for eligible paths still present.") }.padding(.top,14)
            }
        }
    }
    @ViewBuilder private func fileGroup(_ title:String,files:[AppAssociatedFile],review:Bool)->some View {
        if !files.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:8) {
                    Text(title).font(.system(size:12,weight:.semibold))
                    if review { Text("May hold data you want to keep").font(.system(size:11)).foregroundStyle(Palette.muted) }
                    Spacer()
                    if review { let all=files.allSatisfy { plan?.selected.contains($0.id)==true };Button(all ? "Deselect all" : "Select all") { store.setReviewGroup(app.id,selected:!all) }.buttonStyle(QuietTextStyle()).handCursor().disabled(model.busy || running) }
                }.padding(.top,14).padding(.bottom,3)
                ForEach(files) { file in fileRow(file) }
            }
        }
    }
    private func fileRow(_ file:AppAssociatedFile)->some View {
        HStack(alignment:.top,spacing:12) {
            Toggle("Select "+file.kind.rawValue+" for "+app.name,isOn:Binding(get:{plan?.selected.contains(file.id)==true},set:{store.setFile(file.id,appID:app.id,selected:$0)})).toggleStyle(.checkbox).labelsHidden().handCursor().disabled(model.busy || running || !file.selectable).padding(.top,2)
            Text(file.kind.rawValue).font(.system(size:11,weight:.semibold)).frame(width:112,alignment:.leading).padding(.top,2)
            VStack(alignment:.leading,spacing:4) {
                Button { model.reveal(file.item.url) } label: { Text(abbreviated(file.id)).font(.system(size:11,design:.monospaced)).lineLimit(1).truncationMode(.middle).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()) }.buttonStyle(.plain).handCursor().foregroundStyle(Palette.muted).accessibilityLabel("Reveal "+file.id).help(file.item.explanation+"\n"+file.item.confidence+"\n"+file.id)
                if let reason=file.blockedReason { Text(reason).font(.system(size:10)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true) }
                else if file.item.confidence=="App name match; manual review" { Text("Possible app-name match · inspect before selecting").font(.system(size:10)).foregroundStyle(Palette.muted) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Text(file.item.measurement.label).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted).frame(width:102,alignment:.trailing).padding(.top,2)
        }.padding(.vertical,6).bonsaiContextMenu(actions:[
            .init("Reveal in Finder","folder",perform:{model.reveal(file.item.url)}),
            .init("Copy Path","doc.on.doc",perform:{bonsaiCopy(file.id)})
        ]).accessibilityElement(children:.contain).designElement("apps.uninstallRows")
    }
    private func abbreviated(_ path:String)->String { let home=FileManager.default.homeDirectoryForCurrentUser.path;return within(path,home) ? "~"+path.dropFirst(home.count) : path }
}
