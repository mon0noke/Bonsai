import SwiftUI
import AppKit
import BonsaiCore

@MainActor final class CurtainWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
@MainActor final class ScreenCurtain {
    var windows: [NSWindow]=[]; var monitor: Any?; var timer: Timer?
    private var tap:CFMachPort?;private var source:CFRunLoopSource?
    var active:Bool {!windows.isEmpty}
    func toggle() {if active {stop()} else {start()}}
    private func protectInput() {
        // tapCreate performs the actual permission check. Do not block it with
        // a potentially stale AX trust result after a Settings permission change.
        let mask=(CGEventMask(1)<<CGEventType.keyDown.rawValue)|(CGEventMask(1)<<CGEventType.keyUp.rawValue)|(CGEventMask(1)<<14)
        tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{_,type,event,context in
            guard let context else {return Unmanaged.passUnretained(event)}
            let curtain=Unmanaged<ScreenCurtain>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {DispatchQueue.main.async {if let tap=curtain.tap {CGEvent.tapEnable(tap:tap,enable:true)}};return Unmanaged.passUnretained(event)}
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode)==53 {DispatchQueue.main.async {curtain.stop()};return nil}
            if let shortcut=BonsaiShortcut.read("screenShortcut"),UInt32(event.getIntegerValueField(.keyboardEventKeycode))==shortcut.keyCode {
                let flags=event.flags
                let carbon:UInt32=(flags.contains(.maskCommand) ? 256:0)|(flags.contains(.maskShift) ? 512:0)|(flags.contains(.maskAlternate) ? 2048:0)|(flags.contains(.maskControl) ? 4096:0)
                if carbon==shortcut.modifiers {return Unmanaged.passUnretained(event)}
            }
            return nil
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap {source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0);if let source {CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)};CGEvent.tapEnable(tap:tap,enable:true)}
    }
    func start() {
        stop()
        protectInput()
        let duration=ScreenSession.duration(UserDefaults.standard.integer(forKey:"cleanScreenDuration"))
        for display in NSScreen.screens {
            let window=CurtainWindow(contentRect:display.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.level = .screenSaver; window.backgroundColor = .black; window.isReleasedWhenClosed=false; window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            window.contentView=NSHostingView(rootView:VStack(spacing:20) { Spacer(); Text("Screen cleaning mode").font(.title2); Text("Wipe the display gently. Escape or click Exit to return.\n\(self.tap != nil ? "System-wide key protection active." : "Local key protection only; function and media keys may still work.")\nAutomatically exits after \(duration) seconds.").multilineTextAlignment(.center).foregroundStyle(.gray); Button("Exit Clean Screen") { self.stop() }.handCursor().bonsaiPrimary().keyboardShortcut(.cancelAction); Spacer() }.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(.white).background(.black).compactInterface())
            window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps:true)
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { event in if event.keyCode==53 { self.stop() }; return nil }
        timer=Timer.scheduledTimer(withTimeInterval:Double(duration),repeats:false) { _ in Task { @MainActor in self.stop() } }
    }
    func stop() { if let tap {CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)};if let source {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)};tap=nil;source=nil; timer?.invalidate(); timer=nil; if let monitor { NSEvent.removeMonitor(monitor) }; monitor=nil; windows.forEach { $0.close() }; windows=[] }
}
struct CompanionView:View {
    @EnvironmentObject var model:AppModel
    var closePanel:()->Void={}
    var openMain:()->Void={}
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) var dismiss
    @ViewState private var duration=3600.0
    @ViewState private var inputs=false
    @ViewState private var cpuSort=false
    private var snapshot:TelemetrySnapshot {model.snapshot}
    private var counts:ActivityCounts {ActivityCounts(entries:model.history)}
    private var network:NetworkRate? {snapshot.networks.first {$0.interface.hasPrefix("en")}}
    private var memoryPercent:Double {snapshot.memoryTotal>0 ? Double(snapshot.memoryUsed)/Double(snapshot.memoryTotal)*100 : 0}
    private var diskUsed:Double {snapshot.diskTotal>0 ? min(1,max(0,1-Double(snapshot.diskFree)/Double(snapshot.diskTotal))) : 0}
    private var health:HealthAssessment {HealthAssessment.evaluate(snapshot)}
    private var top:[ProcessGroup] {Array(ProcessGrouping.presented(snapshot.processGroups,query:"",sort:cpuSort ? .cpu : .memory,ascending:false,pinned:[]).prefix(3))}
    var body:some View {
        BonsaiScrollView {
            VStack(alignment:.leading,spacing:10) {
                if model.telemetryLoading {BonsaiActivityStrip(title:"Reading your Mac",detail:"Shared live telemetry")}
                overview
                HStack(spacing:10) {cpuCard;gpuCard}
                HStack(spacing:10) {memoryCard;diskCard}
                HStack(spacing:10) {networkCard;thermalCard}
                batteryCard
                processesCard
                toolsCard
                HStack {Button("Open Bonsai") {show(.status)}.buttonStyle(QuietTextStyle()).handCursor();Spacer();Button("Clean") {show(.clean)}.buttonStyle(QuietTextStyle()).handCursor();Button("Quit") {model.shutdown();NSApp.terminate(nil)}.buttonStyle(QuietTextStyle()).handCursor()}.font(.system(size:11)).padding(.horizontal,6)
                TimelineView(.periodic(from:.now,by:1)) {context in Text("Sample \(Int(max(0,context.date.timeIntervalSince(snapshot.date))))s ago · shared live readings").font(.system(size:9)).foregroundStyle(Palette.muted).frame(maxWidth:.infinity,alignment:.center)}
            }.padding(14)
        }.frame(width:392,height:min(840,max(480,(NSScreen.main?.visibleFrame.height ?? 900)-80))).background(Palette.background).bonsaiAppearance()
    }
    private var overview:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Image(systemName:"sun.max.fill").font(.system(size:29)).foregroundStyle(Palette.accent)
                Text(health.title).font(.system(size:29,weight:.bold))
                Spacer()
                Button {inputs.toggle()} label:{Image(systemName:"info.circle").font(.system(size:14))}.buttonStyle(.plain).handCursor().accessibilityLabel("Explain health and measurement inputs")
                    .popover(isPresented:$inputs) {Text("Pressure score: "+HealthAssessment.inputs+" CPU uses tick differences; memory is active + wired + compressed pages. Charts keep 60 samples. Network uses timed counter differences on the first en interface, with fresh baselines after resets. Battery health is a registry estimate. GPU reads conditional AGX driver utilization. CPU/GPU temperatures use supported read-only sensors. Fan control is unavailable. Optional privacy alerts read device-in-use state without recording media or identifying apps; use macOS Control Center for authoritative privacy indicators. Trash moves do not free space until Trash is emptied.").font(.system(size:11)).foregroundStyle(Palette.muted).padding(18).frame(width:330).bonsaiAppearance().compactInterface()}
            }
            HStack(spacing:5) {SourceBadge(text:"\(ProcessInfo.processInfo.processorCount) cores");SourceBadge(text:"\(Int((Double(snapshot.memoryTotal)/1_073_741_824).rounded())) GB");SourceBadge(text:"macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)");SourceBadge(text:"up \(Int(snapshot.uptime/86400)) days")}
        }.padding(.horizontal,3).padding(.bottom,3)
    }
    private func card<Content:View>(_ title:String,_ symbol:String,_ badge:String,color:Color=Palette.sage,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(spacing:5) {Image(systemName:symbol).foregroundStyle(color);Text(title).fontWeight(.semibold);Spacer(minLength:0);if !badge.isEmpty {Text(badge).font(.system(size:9,weight:.semibold)).lineLimit(1).padding(.horizontal,5).padding(.vertical,3).background(Palette.text.opacity(0.06),in:RoundedRectangle(cornerRadius:5))}}
                .font(.system(size:11)).foregroundStyle(Palette.muted)
            content()
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).quietSurface(radius:12)
    }
    private func value(_ text:String,unit:String="")->some View {HStack(alignment:.firstTextBaseline,spacing:3) {Text(text).font(.system(size:25,weight:.bold));if !unit.isEmpty {Text(unit).font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted)}}.lineLimit(1).minimumScaleFactor(0.7)}
    private var cpuCard:some View {
        card("CPU","cpu","Load",color:Palette.sage) {
            value(snapshot.cpu.map {String(format:"%.0f",$0)} ?? "—",unit:"%")
            HistoryPlot(values:model.cpuHistory,color:Palette.sage,bars:true).frame(height:23)
            Text("System utilization").statusNote()
        }
    }
    private var gpuCard:some View {
        card("GPU","display",snapshot.gpu.cores.map {"\($0) cores"} ?? "Driver",color:Palette.accent) {
            value(snapshot.gpu.utilization.map {String(format:"%.0f",$0)} ?? "—",unit:"%")
            HistoryPlot(values:model.gpuHistory,color:Palette.accent,label:"GPU history, up to 60 samples").frame(height:23)
            Text(snapshot.gpu.state).statusNote()
        }
    }
    private var memoryCard:some View {
        card("MEM","memorychip",snapshot.pressure,color:.yellow.opacity(0.7)) {
            value(snapshot.memoryTotal>0 ? String(format:"%.0f",memoryPercent) : "—",unit:"%")
            HistoryPlot(values:model.memoryHistory,color:.yellow.opacity(0.7)).frame(height:23)
            Text(bytes(snapshot.memoryUsed)+" / "+bytes(snapshot.memoryTotal)).statusNote()
        }
    }
    private var diskCard:some View {
        card("Disk","internaldrive",bytes(snapshot.diskTotal),color:.blue.opacity(0.7)) {
            value(snapshot.diskTotal>0 ? bytes(snapshot.diskFree) : "—")
            GeometryReader {g in Capsule().fill(Palette.line).overlay(alignment:.leading) {Capsule().fill(Color.blue.opacity(0.65)).frame(width:g.size.width*diskUsed)}}.frame(height:9).padding(.vertical,7)
            Text(String(format:"%.0f%% used · free above",diskUsed*100)).statusNote()
        }
    }
    private var networkCard:some View {
        card("Network","network",network?.interface ?? "Baseline",color:.cyan) {
            value(network.map {bytes(UInt64(max(0,$0.download+$0.upload)))} ?? "—",unit:"/s")
            NetworkPlot(download:model.networkHistory,upload:model.networkUploadHistory).frame(height:23)
            Text(network.map {"↑ "+bytes(UInt64(max(0,$0.upload)))+" · ↓ "+bytes(UInt64(max(0,$0.download)))} ?? "Waiting for differences").statusNote()
        }
    }
    private var thermalCard:some View {
        card("Thermal","thermometer.medium","macOS",color:Palette.sage) {
            value(snapshot.thermal=="Nominal" ? "Normal" : snapshot.thermal)
            Color.clear.frame(height:23).overlay(alignment:.leading) {Capsule().fill(Palette.line).frame(height:9).overlay(alignment:.leading) {Capsule().fill(snapshot.thermal=="Nominal" ? Palette.sage : Palette.accent).frame(width:70,height:9)}}
            Text("Pressure state · no °C").statusNote()
        }
    }
    private var batteryCard:some View {
        card("Battery","battery.75percent",snapshot.batteryCycles.map {"\($0) cycles"} ?? "Unavailable") {
            HStack {value(snapshot.battery.map {String(format:"%.0f",$0)} ?? "—",unit:"%");Text(snapshot.powerSource).font(.system(size:11)).foregroundStyle(Palette.muted);Spacer();ZStack {Circle().stroke(Palette.line,lineWidth:3);Circle().trim(from:0,to:CGFloat((snapshot.battery ?? 0)/100)).stroke(Palette.sage,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90));Image(systemName:"laptopcomputer").font(.system(size:13))}.frame(width:32,height:32)}
            Text(snapshot.batteryHealth).statusNote()
        }
    }
    private var processesCard:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {Label("Top Processes",systemImage:"chart.bar.xaxis").font(.system(size:11,weight:.semibold)).foregroundStyle(Palette.muted);Spacer();Button("Memory") {cpuSort=false}.buttonStyle(QuietTextStyle()).foregroundStyle(cpuSort ? Palette.muted : Palette.text).handCursor();Button("% CPU") {cpuSort=true}.buttonStyle(QuietTextStyle()).foregroundStyle(cpuSort ? Palette.text : Palette.muted).handCursor()}.font(.system(size:10))
            if top.isEmpty {Text("Waiting for measured processes…").statusNote()}
            ForEach(top) {group in
                Button {model.inspectedProcess=group;show(.status)} label:{HStack {Text(group.name).fontWeight(.semibold).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading);Text(group.hasMemory ? bytes(group.memory)+(group.memoryComplete ? "" : " +") : "—").foregroundStyle(Palette.muted).frame(width:72,alignment:.trailing);Text(group.hasCPU ? String(format:"%.1f",group.cpu)+(group.cpuComplete ? "" : " +") : "—").foregroundStyle(Palette.muted).frame(width:43,alignment:.trailing);Image(systemName:"chevron.right").font(.system(size:8)).foregroundStyle(Palette.muted)}.font(.system(size:11)).monospacedDigit().padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).handCursor().accessibilityLabel("Inspect "+group.name)
            }
        }.padding(12).bonsaiListSurface(radius:12)
    }
    private var toolsCard:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:12) {
                Button {if model.keepAwake {model.awake(false)} else {model.awakeFor(duration>0 ? duration : nil)}} label:{Label("Awake",systemImage:model.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer")}.buttonStyle(QuietTextStyle()).foregroundStyle(model.keepAwake ? Palette.sage : Palette.muted).handCursor().accessibilityValue(model.keepAwake ? "On" : "Off")
                Menu {ForEach([900.0,3600.0,0.0],id:\.self) {seconds in Button(seconds==0 ? "Until quit" : seconds==900 ? "15 minutes" : "1 hour") {duration=seconds;if model.keepAwake {model.awakeFor(seconds>0 ? seconds : nil)}}}} label:{Text(duration==0 ? "Until quit" : duration==900 ? "15 min" : "1h").font(.system(size:9))}.menuStyle(.borderlessButton).fixedSize().handCursor().accessibilityLabel("Keep Screen On duration")
                Spacer(minLength:0)
                Button {dismiss();model.screen.start()} label:{Label("Screen",systemImage:"paintbrush.pointed")}.buttonStyle(QuietTextStyle()).handCursor().help("Clean Screen: Escape or Exit returns; automatic exit in 60 seconds")
            }.font(.system(size:11,weight:.semibold))
            if model.keepAwake {Text(model.awakeDeadline.map {"Releases at "+$0.formatted(date:.omitted,time:.shortened)} ?? "Releases when Bonsai quits").statusNote()}
            Divider().opacity(0.5)
            VStack(alignment:.leading,spacing:12) {
                Label("Local Activity",systemImage:"sparkles").font(.system(size:11,weight:.semibold)).foregroundStyle(Palette.muted)
                HStack {count("\(counts.trashMoves)","Trash moves");count("\(counts.applications)","Apps removed");count("\(counts.maintenanceTasks)","Optimized")}
            }.accessibilityElement(children:.combine)
        }.padding(12).quietSurface(radius:12)
    }
    private func count(_ value:String,_ title:String)->some View {
        VStack(alignment:.leading,spacing:3) {Text(value).font(.system(size:21,weight:.bold));Text(title).font(.system(size:10)).foregroundStyle(Palette.muted)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func show(_ page:AppModel.Page) {model.page=page;dismiss();closePanel();openMain();openWindow(id:"main");NSApp.activate(ignoringOtherApps:true)}
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    var openMain:()->Void={NSApp.windows.first {$0.title=="Bonsai"}?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    var model:AppModel? {didSet {guard let model,controller==nil else {return};controller=MenuCompanionController(model:model);controller?.openMain={[weak self] in self?.openMain()};configureShortcuts();preferences=NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.applyDockPolicy()}}}}
    private var controller:MenuCompanionController?
    private var preferences:NSObjectProtocol?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationWillTerminate(_ notification:Notification) {controller?.stop();GlobalShortcuts.shared.stop();model?.shutdown()}
    func applicationDidFinishLaunching(_ notification:Notification) {NSApp.setActivationPolicy(.regular);NotificationCenter.default.addObserver(self,selector:#selector(windowVisibilityChanged),name:NSWindow.didBecomeMainNotification,object:nil);NotificationCenter.default.addObserver(self,selector:#selector(windowClosed),name:NSWindow.willCloseNotification,object:nil)}
    @objc private func windowVisibilityChanged() {applyDockPolicy()}
    @objc private func windowClosed() {DispatchQueue.main.async {self.applyDockPolicy()}}
    func applyDockPolicy() {
        let mainVisible=NSApp.windows.contains {$0.title=="Bonsai" && $0.isVisible}
        let defaults=UserDefaults.standard
        let hidden=MenuLifecyclePolicy.hideDock(menuVisible:defaults.object(forKey:"menuBarVisible") as? Bool != false,menuOnly:defaults.bool(forKey:"menuBarOnly"),mainWindowVisible:mainVisible)
        NSApp.setActivationPolicy(hidden ? .accessory:.regular)
    }
    func showCompanion() {controller?.togglePanel()}
    func handleQuit() {
        let defaults=UserDefaults.standard
        if MenuLifecyclePolicy.keepRunning(menuVisible:defaults.object(forKey:"menuBarVisible") as? Bool != false,keepMenu:defaults.string(forKey:"quitBehavior")=="Keep Menu Bar") {
            NSApp.windows.filter {$0.title=="Bonsai"}.forEach {$0.close()};applyDockPolicy()
        } else {model?.shutdown();NSApp.terminate(nil)}
    }
    private func configureShortcuts() {
        GlobalShortcuts.shared.actions=["openShortcut":{[weak self] in self?.openMain()},"awakeShortcut":{[weak self] in guard let model=self?.model else {return};if model.keepAwake {model.awake(false)} else {model.awakeFor(3600)}},"screenShortcut":{[weak self] in self?.model?.screen.toggle()}]
        GlobalShortcuts.shared.reload()
    }
}
