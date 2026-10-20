import SwiftUI
import AppKit
import BonsaiCore

struct UninstallButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:14,weight:.semibold)).foregroundStyle(enabled ? Palette.ink : Palette.muted)
            .padding(.horizontal,12).padding(.vertical,4)
            .background(enabled ? Color.white.opacity(1) : Palette.line,in:Capsule())
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.13),value:configuration.isPressed)
    }
}
struct SoftwareUninstallView:View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var summary:UninstallSummary {UninstallSummary(groups:model.uninstallGroups,outcomes:model.uninstallOutcomes)}
    private var items:[AppAssociatedFile] {var seen=Set<String>();return model.uninstallGroups.flatMap {group in group.files.filter {group.selected.contains($0.id)}}.filter {seen.insert($0.id).inserted}}
    var body:some View {
        Group {if model.uninstallScreen == .details {details} else {hero}}
            .animation(reduceMotion ? nil : .easeOut(duration:0.25),value:model.uninstallScreen)
    }
    private var hero:some View {
        GeometryReader {geometry in
            let h=geometry.size.height
            let running=model.uninstallScreen == .run
            let art=BonsaiActivityMotion.portraitSize(height:h,checklist:running)
            BonsaiScrollView {
                VStack(spacing:20) {
                    VStack(spacing:8) {
                        Group {if running {BonsaiActivityPortrait(scene:.elm)} else {NatureIllustration(scene:.elm)}}.frame(width:art,height:art)
                        Text(NatureScene.elm.name).font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                    }
                    VStack(spacing:12) {
                        Text(running ? "Making room for what matters" : summary.headline).font(.system(size:25,weight:.semibold,design:.rounded)).multilineTextAlignment(.center).lineLimit(2)
                        Text(running ? model.progress : bytes(summary.movedBytes)+" moved to Trash · \(summary.removedData) associated \(summary.removedData==1 ? "path" : "paths") removed").font(.system(size:12)).foregroundStyle(Palette.muted).lineLimit(2).truncationMode(.middle)
                        if running {Text(abbreviated(model.uninstallCurrent ?? "Checking identities…")).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)}
                    }.multilineTextAlignment(.center).frame(maxWidth:580).fixedSize(horizontal:false,vertical:true)
                    if running {
                        VStack(alignment:.leading,spacing:9) {
                            if items.isEmpty {HStack(spacing:9) {BonsaiActivityGlyph(size:16);Text("Preparing selected paths").font(.system(size:11,weight:.medium,design:.monospaced));Spacer()}}
                            ForEach(Array(items.prefix(model.uninstallIndex+1).suffix(BonsaiActivityMotion.checklistRows(height:h)))) {file in
                                let outcome=model.uninstallOutcomes.first {$0.path==file.id}
                                HStack(spacing:9) {
                                    if outcome==nil {BonsaiActivityGlyph(size:16)}
                                    else {Image(systemName:outcome?.status=="Trashed" ? "checkmark" : "minus.circle").foregroundStyle(Palette.sage).frame(width:16)}
                                    Text(file.kind.rawValue).font(.system(size:11,weight:.medium,design:.monospaced));Spacer()
                                    Text(outcome?.status ?? "Validating").font(.system(size:10)).foregroundStyle(Palette.muted)
                                }.accessibilityElement(children:.combine)
                            }
                        }.padding(16).frame(width:min(410,geometry.size.width-60)).bonsaiGlass(radius:18)
                        Button("Cancel removal",action:model.cancel).handCursor().buttonStyle(SoftCapsuleStyle()).keyboardShortcut(.cancelAction)
                    } else {
                        VStack(spacing:12) {
                            Button {model.uninstallScreen = .details} label:{Text("Review results").frame(width:220,height:38)}.buttonStyle(UninstallButtonStyle()).handCursor().bonsaiDefaultAction()
                            Button("Back to apps") {model.uninstallScreen = .list}.buttonStyle(QuietTextStyle()).handCursor()
                        }
                    }
                }.padding(.vertical,20).frame(maxWidth:.infinity).frame(minHeight:h)
            }
        }
    }
    private var details:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:8) {
                    Text("Uninstall details").font(.system(size:24,weight:.semibold,design:.rounded))
                    Text("\(summary.removedApps) app\(summary.removedApps==1 ? "" : "s") removed · \(summary.removedData) associated paths · \(keptCount) kept · \(summary.failed) skipped · \(summary.cancelled) cancelled").font(.system(size:12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button {model.uninstallScreen = .complete} label:{Image(systemName:"xmark.circle.fill").font(.system(size:21)).foregroundStyle(Palette.muted)}.buttonStyle(.plain).handCursor().accessibilityLabel("Close uninstall details").keyboardShortcut(.cancelAction)
            }.padding(.top,18)
            BonsaiScrollView {
                LazyVStack(alignment:.leading,spacing:22) {
                    ForEach(model.uninstallGroups) {group in
                        VStack(alignment:.leading,spacing:12) {
                            HStack(spacing:12) {
                                Image(nsImage:model.software.icon(group.app)).resizable().frame(width:32,height:32).accessibilityHidden(true)
                                VStack(alignment:.leading,spacing:4) {Text(group.app.name).font(.system(size:14,weight:.semibold));Text(abbreviated(group.id)).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted)}
                            }
                            ForEach(group.files) {file in UninstallResultRow(file:file,selected:group.selected.contains(file.id),outcome:model.uninstallOutcomes.first {$0.path==file.id})}
                        }.padding(18).bonsaiListSurface(radius:16)
                    }

                }.padding(.bottom,12)
            }
            HStack {Text(model.uninstallDate?.formatted(date:.abbreviated,time:.shortened) ?? "").font(.system(size:10)).foregroundStyle(Palette.muted);Spacer();Button("Back to apps") {model.uninstallScreen = .list}.buttonStyle(SoftCapsuleStyle()).handCursor()}
        }.padding(.bottom,12)
    }
    private var keptCount:Int {
        var seen=Set<String>()
        return model.uninstallGroups.flatMap {group in group.files.filter {!group.selected.contains($0.id)}}.filter {seen.insert($0.id).inserted}.count
    }
    private func abbreviated(_ path:String)->String {let home=FileManager.default.homeDirectoryForCurrentUser.path;return within(path,home) ? "~"+path.dropFirst(home.count) : path}
}

private struct UninstallResultRow:View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var expanded=false
    let file:AppAssociatedFile
    let selected:Bool
    let outcome:ItemOutcome?
    private var trashed:Bool {outcome?.status=="Trashed"}
    private var state:String {outcome?.status ?? "Kept"}
    private var symbol:String {trashed ? "checkmark.circle" : selected ? "exclamationmark.circle" : "minus.circle"}
    private var size:String {file.item.measurement.allocated==0 ? "0 KB" : file.item.measurement.label}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {toggle;reveal}
            if expanded {detail.padding(.leading,28).padding(.bottom,12).transition(.opacity)}
        }.accessibilityElement(children:.contain)
    }
    private var toggle:some View {
        Button {withAnimation(reduceMotion ? nil : .easeOut(duration:0.18)) {expanded.toggle()}} label:{header}
            .buttonStyle(.plain).handCursor()
            .accessibilityLabel((expanded ? "Collapse " : "Expand ")+file.kind.rawValue+", "+file.id+", "+state)
            .help(file.id+"\nClick for the outcome and recovery details.")
    }
    private var header:some View {
        HStack(spacing:12) {
            Image(systemName:symbol).foregroundStyle(trashed ? Palette.sage : Palette.muted).frame(width:16)
            Text(file.kind.rawValue).font(.system(size:11,weight:.semibold)).frame(width:106,alignment:.leading)
            Text(abbreviated(file.id)).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth:.infinity,alignment:.leading)
            Text(size).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted).frame(width:78,alignment:.trailing)
            Text(state).font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.muted).frame(width:62,alignment:.trailing)
            Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)).rotationEffect(Angle.degrees(expanded ? 180.0 : 0.0)).foregroundStyle(Palette.muted)
        }.padding(.vertical,12).contentShape(Rectangle())
    }
    private var reveal:some View {
        Button {
            if trashed,outcome?.recovery==nil {model.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))}
            else {model.reveal(URL(fileURLWithPath:outcome?.recovery ?? file.id))}
        } label:{Image(systemName:"arrow.up.right.square").font(.system(size:12)).frame(width:24,height:28)}
            .buttonStyle(.plain).foregroundStyle(Palette.muted).handCursor()
            .accessibilityLabel((trashed ? "Show in Trash: " : "Reveal: ")+file.kind.rawValue)
            .help(trashed ? "Show in Trash" : "Reveal in Finder")
    }
    private var detail:some View {
        VStack(alignment:.leading,spacing:7) {
            Text(outcome?.detail ?? (selected ? "No result available. Check Finder before retrying." : "Kept · not selected for removal.")).font(.system(size:11)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
            Text("Original: "+abbreviated(file.id)).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
            if let recovery=outcome?.recovery {Text("Recover from: "+abbreviated(recovery)).font(.system(size:10,design:.monospaced)).textSelection(.enabled)}
        }
    }
    private func abbreviated(_ path:String)->String {let home=FileManager.default.homeDirectoryForCurrentUser.path;return within(path,home) ? "~"+path.dropFirst(home.count) : path}
}
