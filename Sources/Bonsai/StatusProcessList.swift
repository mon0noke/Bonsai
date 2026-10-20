import SwiftUI
import AppKit
import BonsaiCore

private struct StatusColumns {
    let memory:CGFloat,cpu:CGFloat,power:CGFloat,pid:CGFloat
    let actions:CGFloat=24
    init(width:CGFloat) {
        let available=max(500,width-18-44-60-24)
        memory=max(90,available*0.16);cpu=max(148,available*0.22)
        power=max(76,available*0.12);pid=max(64,available*0.10)
    }
}
struct StatusProcessList:View {
    @EnvironmentObject var model:AppModel
    @ViewState private var sort:ProcessSortKey = .memory
    @ViewState private var ascending=false
    @ViewState private var terminate:ProcessSample?
    @ViewState private var force=false
    @ViewState private var icons:[String:NSImage]=[:]
    private var rows:[ProcessGroup] {ProcessGrouping.presented(model.snapshot.processGroups,query:"",sort:sort,ascending:ascending,pinned:model.pinned)}
    private var appPaths:[String] {model.snapshot.processGroups.compactMap { $0.applicationURL?.path }.sorted()}
    var body:some View {
        GeometryReader {geometry in
        let columns=StatusColumns(width:geometry.size.width)
        VStack(spacing:0) {
            HStack(spacing:12) {
                sortButton("NAME (\(rows.count))",.name).frame(maxWidth:.infinity,alignment:.leading)
                sortButton("MEM",.memory).frame(width:columns.memory,alignment:.trailing)
                sortButton("% CPU",.cpu).frame(width:columns.cpu,alignment:.trailing)
                sortButton("PWR",.power).frame(width:columns.power,alignment:.trailing).help("Energy impact score. Lower is better. Includes CPU use and idle wakeups; not watts or a percentage.")
                sortButton("PID",.pid).frame(width:columns.pid,alignment:.trailing)
                Color.clear.frame(width:columns.actions,height:1)
            }.font(.system(size:10,weight:.bold)).foregroundStyle(Palette.muted).padding(.trailing,18).padding(.horizontal,22).padding(.vertical,10)
            BonsaiScrollView {
                LazyVStack(spacing:1) {
                    ForEach(rows) {group in StatusProcessRow(group:group,columns:columns,icon:group.applicationURL.flatMap {icons[$0.path]},isPinned:isPinned(group),inspect:{model.inspectedProcess=group},actions:processActions(group))}
                    if rows.isEmpty {EmptyState(symbol:"magnifyingglass",title:"No matching processes",detail:"Waiting for a measured sample.").padding(24)}
                }.padding(.vertical,4)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityLabel("App and process list")
        }.frame(maxWidth:.infinity,maxHeight:.infinity).bonsaiListSurface(radius:13).clipShape(RoundedRectangle(cornerRadius:13))
        }
        .onAppear(perform:updateIcons).onChange(of:appPaths) {_,_ in updateIcons()}
        .alert(force ? "Force quit this process?":"Terminate this process?",isPresented:Binding(get:{terminate != nil},set:{if !$0 {terminate=nil}})) {
            Button("Cancel",role:.cancel) {terminate=nil}
            Button(force ? "Force Quit":"Terminate",role:.destructive) {if let p=terminate {model.terminate(p,force:force)};terminate=nil}
        } message:{Text("\(terminate?.name ?? "This process") may have unsaved work.")}
    }
    private func processActions(_ group:ProcessGroup)->[BonsaiMenuAction] {
        let p=group.representative
        var items:[BonsaiMenuAction]=[
            .init(isPinned(group) ? "Unpin Row":"Pin Row","pin",perform:{model.togglePin(group)}),
            .init("Why is this running?","lightbulb",group:1,perform:{model.inspectedProcess=group})
        ]
        if let url=group.applicationURL ?? (p.executable.hasPrefix("/") ? URL(fileURLWithPath:p.executable):nil) {items.append(.init("Reveal in Finder","folder",group:1,perform:{model.reveal(url)}))}
        items += [
            .init("Copy Process Name","doc.on.doc",group:2,perform:{bonsaiCopy(group.name)}),
            .init("Copy PID","doc.on.doc",group:2,perform:{bonsaiCopy(String(p.pid))}),
            .init("Terminate","rectangle.portrait.and.arrow.right",group:3,destructive:true,enabled:controllable(p) && !model.busy,perform:{force=false;terminate=p}),
            .init("Force Quit","xmark.circle",group:3,destructive:true,enabled:controllable(p) && !model.busy,perform:{force=true;terminate=p})
        ]
        return items
    }
    private func sortButton(_ title:String,_ key:ProcessSortKey)->some View {
        Button {if sort==key {ascending.toggle()} else {sort=key;ascending=key == .name || key == .pid}} label: {
            HStack(spacing:4) {Text(title);if sort==key {Image(systemName:ascending ? "arrow.up" : "arrow.down").font(.system(size:8,weight:.bold))}}
                .foregroundStyle(sort==key ? Palette.text : Palette.muted)
        }.buttonStyle(.plain).handCursor().accessibilityLabel("Sort processes by "+key.rawValue).accessibilityValue(sort==key ? (ascending ? "Ascending" : "Descending") : "Not selected").accessibilityAddTraits(sort==key ? .isSelected : [])
    }
    private func isPinned(_ group:ProcessGroup)->Bool {model.pinned.contains(group.pinKey) || model.pinned.contains(group.name)}
    private func updateIcons() {
        var next:[String:NSImage]=[:]
        for path in Set(appPaths) {next[path]=icons[path] ?? NSWorkspace.shared.icon(forFile:path)}
        icons=next
    }
}
private struct StatusProcessRow:View {
    let group:ProcessGroup;let columns:StatusColumns;let icon:NSImage?;let isPinned:Bool;let inspect:()->Void
    let actions:[BonsaiMenuAction]
    @ViewState private var hovering=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bonsaiMotionSuppressed) private var interactionsSuppressed
    private var memoryText:String {group.hasMemory ? bytes(group.memory)+(group.memoryComplete ? "" : " +") : "—"}
    private var cpuText:String {group.hasCPU ? String(format:"%.1f",group.cpu)+(group.cpuComplete ? "" : " +") : "—"}
    private var powerText:String {group.powerScore.map {String(format:"%.1f",$0)+(group.powerScoreComplete ? "":" +")} ?? "—"}
    private var cpuColor:Color {switch StatusMetricLabels.cpuSeverity(group.cpu) {case 2:return Color(red:0.94,green:0.43,blue:0.37);case 1:return Color(red:0.86,green:0.65,blue:0.38);default:return Palette.muted}}
    private var accessibilitySummary:String {[processCount(group),"memory "+memoryLabel(group),"CPU "+cpuLabel(group),"power score "+powerText,"PID \(group.representative.pid)"].joined(separator:", ")}
    var body:some View {
        HStack(spacing:12) {
            Button(action:inspect) {
                HStack(spacing:12) {
                    HStack(spacing:9) {
                        RoundedRectangle(cornerRadius:1).fill(isPinned ? Palette.accent : group.cpu>30 ? Palette.accent.opacity(0.75) : Palette.line).frame(width:3,height:15)
                        if let icon {Image(nsImage:icon).resizable().frame(width:18,height:18).accessibilityHidden(true)}
                        else {Image(systemName:"terminal").foregroundStyle(Palette.muted).frame(width:18).accessibilityHidden(true)}
                        Text(group.name).font(.system(size:12,weight:.semibold)).lineLimit(1)
                        if isPinned {Image(systemName:"pin.fill").font(.system(size:9)).foregroundStyle(Palette.accent).accessibilityHidden(true)}
                        if group.members.count>1 {Text("\(group.members.count)").font(.system(size:9)).foregroundStyle(Palette.muted).padding(.horizontal,5).padding(.vertical,2).background(Palette.line,in:Capsule())}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Text(memoryText).font(.system(size:12)).monospacedDigit().foregroundStyle(Palette.muted).frame(width:columns.memory,alignment:.trailing)
                    HStack(spacing:12) {
                        CPUUsageBar(value:group.cpu,known:group.hasCPU,color:cpuColor).frame(width:min(100,max(58,columns.cpu-66)),height:6)
                        Text(cpuText).font(.system(size:12)).monospacedDigit().foregroundStyle(cpuColor).frame(width:54,alignment:.trailing)
                    }.frame(width:columns.cpu,alignment:.trailing)
                    Text(powerText).font(.system(size:11)).monospacedDigit().foregroundStyle(Palette.muted).frame(width:columns.power,alignment:.trailing)
                    Text(String(group.representative.pid)).font(.system(size:11)).monospacedDigit().foregroundStyle(Palette.muted.opacity(0.75)).frame(width:columns.pid,alignment:.trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).handCursor().accessibilityLabel("Inspect "+group.name).accessibilityValue(accessibilitySummary).help("Inspect this app and its measured helper processes")
            BonsaiActionMenu(label:"Process actions for "+group.name,actions:actions,triggerHeight:24).frame(width:columns.actions)
        }.padding(.horizontal,16).padding(.vertical,4)
        .background(Palette.text.opacity(hovering && !interactionsSuppressed ? 0.065 : 0),in:RoundedRectangle(cornerRadius:10))
        .contentShape(Rectangle())
        .background(StatusRowHover(hovering:$hovering,enabled:!interactionsSuppressed).accessibilityHidden(true))
        .onChange(of:interactionsSuppressed) {_,value in if value {hovering=false}}
        .onDisappear {hovering=false}
        .onChange(of:group.id) {_,_ in hovering=false}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) {_ in hovering=false}
        .animation(reduceMotion ? nil : .easeOut(duration:0.07),value:hovering)
        .accessibilityElement(children:.contain)
        .bonsaiContextMenu(actions:actions).padding(.horizontal,6).designElement("status.rows")
    }
}
private func controllable(_ p:ProcessSample)->Bool {p.uid==getuid() && p.pid>1 && p.pid != getpid()}
private func terminationMessage(_ p:ProcessSample?)->String {"\(p?.name ?? "Process") (PID \(p?.pid ?? 0)) may have unsaved work. Only this identity is sent SIGTERM; other members are untouched. Its PID, owner and start time are revalidated. Quit normally when possible."}
private func copy(_ text:String) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)}

private func processCount(_ group:ProcessGroup)->String {group.members.count==1 ? "1 process" : "\(group.members.count) processes"}
private func memoryLabel(_ group:ProcessGroup)->String {group.hasMemory ? bytes(group.memory)+(group.memoryComplete ? "" : " + partial") : "unavailable"}
private func cpuLabel(_ group:ProcessGroup)->String {group.hasCPU ? String(format:"%.1f%%",group.cpu)+(group.cpuComplete ? "" : " + partial") : "unavailable"}

private struct CPUUsageBar:View {
    let value:Double;let known:Bool;let color:Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GeometryReader {geometry in
            ZStack(alignment:.leading) {
                Capsule().fill(Palette.text.opacity(0.075))
                if known && value>0 {Capsule().fill(LinearGradient(colors:[color.opacity(0.65),color],startPoint:.leading,endPoint:.trailing)).frame(width:max(1,geometry.size.width*min(1,max(0,value/100))))}
            }
        }.animation(reduceMotion ? nil:.easeOut(duration:0.3),value:value).accessibilityHidden(true)
    }
}
