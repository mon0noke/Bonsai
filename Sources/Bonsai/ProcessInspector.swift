import SwiftUI
import AppKit
import BonsaiCore

struct StatusProcessInspector:View {
    @EnvironmentObject var model:AppModel
    let initial:ProcessGroup
    let onClose:()->Void
    @ViewState private var selected:ProcessSample?
    @ViewState private var details:ProcessDetails?
    @ViewState private var loading=true
    @ViewState private var expanded=false
    @ViewState private var confirmation=false
    @ViewState private var force=false
    @FocusState private var closeFocused:Bool
    private let collector=ProcessDetailCollector()
    private var live:ProcessGroup? {ProcessInspection.liveGroup(initial,in:model.snapshot.processGroups)}
    private var group:ProcessGroup {live ?? initial}
    private var target:ProcessSample {selected ?? initial.representative}
    private var current:ProcessSample? {live?.members.first {$0.id==target.id && $0.uid==target.uid}}
    private var members:[ProcessSample] {group.members.sorted {$0.memory==$1.memory ? $0.pid<$1.pid : $0.memory>$1.memory}}
    private var parents:[ProcessSample] {ProcessInspection.parents(of:target,in:model.snapshot.processes)}
    private var user:String {details?.user ?? "UID \(target.uid)"}
    private var canControl:Bool {current != nil && target.uid==getuid() && target.pid>1 && target.pid != getpid() && !model.busy}
    private var summary:String {
        "\(group.members.count) \(group.members.count==1 ? "process" : "processes") · CPU "+(group.hasCPU ? (group.cpuComplete ? "" : "At least ")+String(format:"%.1f%%",group.cpu) : "—")+" · MEM "+(group.hasMemory ? Measurement.sizeLabel(group.memory,complete:group.memoryComplete) : "—")+" · "+user
    }
    private var revealURL:URL? {group.applicationURL ?? (target.executable.isEmpty ? nil : URL(fileURLWithPath:target.executable))}
    private var inspectionKey:String {target.id+":"+String(model.snapshot.date.timeIntervalSince1970)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {
                if let url=revealURL {Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:38,height:38).accessibilityHidden(true)}
                else {Image(systemName:"terminal").font(.system(size:28)).foregroundStyle(Palette.sage)}
                Text(group.name).font(.system(size:25,weight:.bold)).lineLimit(1)
                Spacer()
                Button(action:onClose) {Image(systemName:"xmark").font(.system(size:14,weight:.medium)).frame(width:32,height:32).background(Palette.text.opacity(0.07),in:Circle())}.buttonStyle(.plain).handCursor().accessibilityLabel("Close process details").keyboardShortcut(.cancelAction).focusable().focusEffectDisabled().focused($closeFocused)
            }.padding(22)
            Divider().opacity(0.45)
            BonsaiScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text(summary).font(.system(size:12,weight:.medium)).foregroundStyle(Palette.muted)
                    HStack(spacing:6) {
                        if parents.isEmpty && target.parentPID>0 {Text("Parent PID \(target.parentPID)").foregroundStyle(Palette.muted);Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Palette.muted.opacity(0.6))}
                        ForEach(parents) {p in Text(p.name+" \(p.pid)").foregroundStyle(Palette.muted);Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Palette.muted.opacity(0.6))}
                        Text(target.name).fontWeight(.semibold);Text(String(target.pid)).foregroundStyle(Palette.muted)
                    }.font(.system(size:12)).lineLimit(1).help("Measured parent ancestry; not a launch-reason inference")
                    if current==nil {Text("This process has exited or is absent from the current sample. Controls are disabled; its last sampled details remain here.").font(.system(size:11)).foregroundStyle(.orange)}
                    Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:10) {
                        detailRow("Confidence",group.applicationURL == nil ? "Individual process identity" : "Bundle/path association")
                        detailRow("Evidence",group.applicationURL?.path ?? target.executable)
                        detailRow("Launch reason","Not reported by supported APIs")
                        detailRow("Launch service","Not reported by supported APIs")
                        detailRow("Threads",details?.threads.map(String.init) ?? unavailable)
                        detailRow("Open Files",details?.openFiles.map(String.init) ?? unavailable)
                        detailRow("Disk I/O",details?.bytesRead.map {bytes($0)+" R · "+bytes(details?.bytesWritten ?? 0)+" W"} ?? unavailable)
                        detailRow("User",user)
                        detailRow("Started",target.start>0 ? Date(timeIntervalSince1970:Double(target.start)).formatted(date:.abbreviated,time:.shortened) : "Unavailable")
                        detailRow("Working Directory",details?.workingDirectory ?? unavailable)
                        detailRow("Executable",target.executable.isEmpty ? "Unavailable" : target.executable)
                    }.font(.system(size:12))
                    HStack {Text("Processes").fontWeight(.semibold);Spacer();Text("By memory")}.font(.system(size:11)).foregroundStyle(Palette.muted)
                    VStack(spacing:4) {
                        ForEach(expanded ? members : Array(members.prefix(6))) {p in
                            Button {selected=p;details=nil;loading=true} label: {
                                HStack(spacing:10) {
                                    Text(p.name).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                                    Text(String(p.pid)).foregroundStyle(Palette.muted).frame(width:54,alignment:.trailing)
                                    Text(p.cpuAvailable ? String(format:"%.1f%%",p.cpu) : "—").foregroundStyle(Palette.muted).frame(width:52,alignment:.trailing)
                                    Text(p.metricsAvailable ? bytes(p.memory) : "—").frame(width:75,alignment:.trailing)
                                }.font(.system(size:11)).monospacedDigit().padding(.vertical,5).padding(.horizontal,5).contentShape(Rectangle())
                                    .background(p.id==target.id ? Palette.text.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:6))
                            }.buttonStyle(.plain).handCursor().accessibilityLabel("Inspect \(p.name), PID \(p.pid)").accessibilityValue(p.id==target.id ? "Selected" : "")
                        }
                        if members.count>6 {Button(expanded ? "Show fewer processes" : "\(members.count-6) more \(members.count==7 ? "process" : "processes")") {expanded.toggle()}.buttonStyle(QuietTextStyle()).handCursor().frame(maxWidth:.infinity,alignment:.leading)}
                    }
                    Text("Resident totals can include shared pages. CPU can exceed 100%. Disk I/O counters are cumulative for the selected process. Parent paths describe measured ancestry, not why it launched.").font(.system(size:10)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
                    if loading {BonsaiActivityStrip(title:"Reading process details",detail:"Checking this process identity")}
                    Text(details.map {"Details sampled "+$0.sampledAt.formatted(date:.omitted,time:.standard)} ?? (loading ? "Reading process details…" : "Details unavailable: process exited, changed identity, or access was denied.")).font(.system(size:10)).foregroundStyle(Palette.muted)
                }.padding(20)
            }
            HStack(spacing:8) {
                Button("Copy Summary") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(clipboardSummary,forType:.string)}.buttonStyle(SoftCapsuleStyle()).handCursor()
                Button("Reveal") {if let url=revealURL {model.reveal(url)}}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(revealURL==nil)
                Spacer(minLength:0)
                Button("Terminate") {force=false;confirmation=true}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(!canControl)
                Button {force=true;confirmation=true} label:{Text("Force Quit").foregroundStyle(.red)}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(!canControl)
            }.font(.system(size:12,weight:.semibold)).padding(20)
        }.foregroundStyle(Palette.text).accessibilityElement(children:.contain).accessibilityLabel("Process details for "+group.name)
        .onAppear {closeFocused=true}
        .task(id:inspectionKey) {
            let identity=target;let value=await collector.read(identity)
            guard !Task.isCancelled,target.id==identity.id else {return}
            details=value;loading=false
        }
        .alert(force ? "Force quit this process?" : "Terminate this process?",isPresented:$confirmation) {
            Button("Cancel",role:.cancel) {}
            Button(force ? "Force Quit" : "Terminate",role:.destructive) {let identity=target;onClose();model.terminate(identity,force:force)}
        } message: {Text("\(target.name) (PID \(target.pid)) may have unsaved work. "+(force ? "Force Quit sends SIGKILL immediately and can lose unsaved changes. " : "Terminate sends SIGTERM so the process can exit gracefully. ")+"Only this process is targeted. Its owner, PID and exact start time are checked again before sending the signal.")}
    }
    private var unavailable:String {loading ? "Reading…" : "Unavailable"}
    private func detailRow(_ label:String,_ value:String)->some View {
        GridRow {Text(label).foregroundStyle(Palette.muted).frame(width:124,alignment:.trailing);Text(value.isEmpty ? "Unavailable" : value).foregroundStyle(Palette.text.opacity(0.85)).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}
    }
    private var clipboardSummary:String {
        let io=details?.bytesRead.map {bytes($0)+" R · "+bytes(details?.bytesWritten ?? 0)+" W"} ?? "Unavailable"
        let rows=[group.name,summary,"PID \(target.pid) · "+user,"Parent PID: \(target.parentPID)","Evidence: "+(group.applicationURL?.path ?? target.executable),"Launch reason/service: not reported by supported APIs","Threads: "+(details?.threads.map(String.init) ?? "Unavailable"),"Open files: "+(details?.openFiles.map(String.init) ?? "Unavailable"),"Disk I/O: "+io,"Started: "+Date(timeIntervalSince1970:Double(target.start)).formatted(date:.abbreviated,time:.shortened),"Working directory: "+(details?.workingDirectory ?? "Unavailable"),"Executable: "+target.executable,"Processes:"]
        return rows.joined(separator:"\n")+"\n"+members.map {"\($0.name) · PID \($0.pid) · "+($0.metricsAvailable ? bytes($0.memory) : "Unavailable")}.joined(separator:"\n")
    }
}
