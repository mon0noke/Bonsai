import SwiftUI
import AppKit
import BonsaiCore

struct SoftwareUpdatesPanel:View {
    @EnvironmentObject private var model:AppModel
    @ObservedObject var updates:SoftwareUpdatesStore
    @ObservedObject var software:SoftwareStore
    @ViewState private var quitUpdate:SoftwareUpdate?
    var query:String
    var available:[SoftwareUpdate] {software.sort.sortedUpdates(updates.items.filter {query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)},inventory:model.apps)}
    var installed:[InstalledApp] {
        let updated=Set(updates.items.compactMap { $0.applicationURL.map {physicalURL($0).path} })
        return software.visible(model.apps,query:query,revision:model.inventoryRevision).filter {!updated.contains($0.id)}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                Text("Available updates").font(.system(size:12,weight:.semibold))
                Text("\(updates.items.count)").secondaryText()
                Spacer()
                if updates.checking {Text("Checking…").secondaryText()}
                else if let date=updates.date {Text(date.formatted(date:.omitted,time:.shortened)).secondaryText()}
                Button("Update All") {model.updateAll(SoftwareUpdateBatch.plan(updates.items).filter(\.canInstall))}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy || updates.checking || !updates.items.contains(where:{$0.canInstall})).help("Install supported updates inside Bonsai")
            }
            if updates.checking {SoftwareRefreshStatus(title:"Checking update sources · \(updates.inspected) checked",cancel:updates.cancel)}
            if let failure=updates.failure {HStack {Text(failure).secondaryText();Spacer();Button("Retry",action:model.checkUpdates).buttonStyle(QuietTextStyle()).handCursor()}}
            LazyVStack(spacing:6) {ForEach(available) {item in
                UpdateAppRow(name:item.name,url:item.applicationURL,detail:item.installed+" → "+item.available,badge:item.sourceLabel,alternate:false,issue:updates.issues[item.id],app:model.apps.first {$0.id==item.applicationURL.map {physicalURL($0).path}}) {
                    if let activity=updates.installations[item.id] {
                        UpdateRowProgress(name:item.name,activity:activity)
                    } else if item.canPrepareInstaller {
                        Button("Update") {
                            if model.preparedInstallers[item.id]==nil {model.downloadInstaller(item)} else {model.openPreparedInstaller(item)}
                        }.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy || updates.checking)
                            .accessibilityLabel("Update "+item.name)
                    } else if item.canInstall {
                        Button("Update") {if model.updateAppIsRunning(item) {quitUpdate=item} else {model.install(item)}}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy || updates.checking)
                            .accessibilityLabel("Update "+item.name).help("Download and install inside Bonsai")
                    } else {
                        Button("Update") {model.handoffUpdate(item)}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy)
                            .accessibilityLabel("Update "+item.name).help("This publisher requires its own updater or installer")
                    }
                }
            }}
            if available.isEmpty && !query.isEmpty && installed.isEmpty {EmptyState(symbol:"magnifyingglass",title:"No matching apps",detail:"Try another application name.")}
            else if updates.items.isEmpty {Text(updates.checking ? "Available updates appear as sources finish checking." : updates.date==nil ? "Available updates will appear here." : "No updates found in checked sources.").secondaryText().padding(.vertical,8)}
            HStack {Text("Installed Apps").font(.system(size:12,weight:.semibold));Text("\(installed.count)").secondaryText();Spacer()}.padding(.top,12)
            LazyVStack(spacing:6) {ForEach(Array(installed.enumerated()),id:\.element.id) {index,app in
                UpdateAppRow(name:app.name,url:app.url,detail:app.version+" · "+(app.measurement.files==0 ? "Measuring…" : app.measurement.label),badge:availability(app),alternate:index%2==1,app:app) {
                    Button("Reveal in Finder") {model.reveal(app.url)}.buttonStyle(QuietTextStyle()).handCursor().accessibilityLabel("Reveal "+app.name+" in Finder")
                    Button("Uninstall") {inspectRemoval(app.url)}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy).accessibilityLabel("Uninstall "+app.name)
                }
            }}
        }.confirmationDialog("Quit \(quitUpdate?.name ?? "app") to update?",isPresented:Binding(get:{quitUpdate != nil},set:{if !$0 {quitUpdate=nil}}),titleVisibility:.visible) {
            if let item=quitUpdate {Button("Quit & Update") {model.install(item,quitFirst:true);quitUpdate=nil}}
            Button("Cancel",role:.cancel) {quitUpdate=nil}
        } message: {Text("Save your work before continuing.")}
    }
    func availability(_ app:InstalledApp)->String {
        if updates.checking {return "Checking"}
        return updates.appStates[app.id] ?? "Check in app"
    }
    func inspectRemoval(_ url:URL) {
        guard let app=model.apps.first(where:{$0.id==physicalURL(url).path}) else {model.error="This application moved. Refresh the inventory and try again.";return}
        software.clear();model.softwareTab="Uninstall";software.activateApp(app,inventory:model.apps,policy:model.softwarePolicy)
    }
}
struct UpdateRowProgress:View {
    var name:String
    var activity:SoftwareUpdateProgress
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(spacing:4) {
                Text(activity.phase.title)
                Spacer(minLength:0)
                if let fraction=activity.fraction {Text("\(Int(fraction*100))%").monospacedDigit()}
            }.font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted)
            if activity.phase != .queued {
                if let fraction=activity.fraction {
                    ProgressView(value:fraction).progressViewStyle(.linear).controlSize(.mini).tint(Palette.accent)
                        .accessibilityLabel("Updating "+name+", "+activity.phase.title)
                } else {
                    ProgressView().progressViewStyle(.linear).controlSize(.mini).tint(Palette.accent)
                        .accessibilityLabel("Updating "+name+", "+activity.phase.title)
                }
            }
        }.frame(width:96).accessibilityElement(children:.combine)
    }
}
private struct UpdateAppRow<Actions:View>:View {
    var name:String;var url:URL?;var detail:String;var badge:String;var alternate:Bool;var issue:String?=nil;var app:InstalledApp?=nil
    @ViewBuilder var actions:Actions
    @ViewState private var hovering=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        HStack(spacing:14) {
            if let url {Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:32,height:32).accessibilityHidden(true)}
            else {Image(systemName:"shippingbox").font(.system(size:23)).foregroundStyle(Palette.muted).frame(width:32)}
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:8) {
                    Text(name).font(.system(size:13,weight:.semibold))
                    if let issue {Image(systemName:"exclamationmark.circle.fill").font(.system(size:12)).foregroundStyle(Palette.accent).help(issue).accessibilityLabel("Update failed: "+issue)}
                    Text(badge).font(.system(size:10)).foregroundStyle(Palette.muted)}
                HStack(spacing:7) {Text(detail).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1);if let app {AppActivityLabels(app:app)}}
            }.frame(maxWidth:.infinity,alignment:.leading)
            actions
        }.padding(.horizontal,16).padding(.vertical,14)
            .background(Palette.text.opacity(hovering ? 0.085 : 0),in:RoundedRectangle(cornerRadius:13))
            .onHover {hovering=$0}.animation(reduceMotion ? nil : .easeOut(duration:0.16),value:hovering)
            .accessibilityElement(children:.contain).designElement("apps.updateRows")
    }
}
