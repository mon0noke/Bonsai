import SwiftUI
import AppKit
import ServiceManagement
import BonsaiCore

struct StatusView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @ViewState var showInterfaces=false; @ViewState var showInputs=false
    @AppStorage("temperatureUnit") private var temperatureUnit=TemperatureUnit.celsius.rawValue
    @ViewState private var showBatteryDevices=false
    @ViewState private var dialogID=UUID()
    @FocusState private var healthCloseFocused:Bool
    @FocusState private var networkCloseFocused:Bool

    var primary:NetworkRate? {model.snapshot.networks.first {$0.interface==model.snapshot.primaryInterface} ?? model.snapshot.networks.first {$0.interface.hasPrefix("en")}}
    private var pressureLabel:String {StatusMetricLabels.memoryPressure(model.snapshot.pressure,utilization:memoryPercent)}
    private var thermalLabel:String {model.snapshot.thermal=="Nominal" ? "Normal":model.snapshot.thermal}
    private func temperature(_ value:Double?)->String {guard let value else {return "—"};return (TemperatureUnit(rawValue:temperatureUnit) ?? .celsius).format(celsius:value)}
    private var connectionLabel:String {guard let primary else {return "—"};return model.snapshot.networkNames[primary.interface] ?? NetworkConnectionLabels.fallback(primary.interface)}
    var memoryPercent:Double { model.snapshot.memoryTotal>0 ? Double(model.snapshot.memoryUsed)/Double(model.snapshot.memoryTotal)*100 : 0 }
    var diskUsed:Double { model.snapshot.diskTotal>0 ? Double(model.snapshot.diskTotal>=model.snapshot.diskFree ? model.snapshot.diskTotal-model.snapshot.diskFree : 0)/Double(model.snapshot.diskTotal) : 0 }
    var health:HealthAssessment {HealthAssessment.evaluate(model.snapshot)}
    var body:some View {
        GeometryReader { bounds in
        let dashboardHeight=min(448,max(340,bounds.size.height*0.62))
        VStack(alignment:.leading,spacing:16) {
            if model.telemetryLoading {BonsaiActivityStrip(title:"Reading your Mac",detail:"Collecting the first live sample")}
            GeometryReader { geometry in
                let unit=max(0,(geometry.size.width-42)/4.2)
                VStack(spacing:14) {
                    HStack(spacing:14) {
                        healthCard.frame(width:unit*1.2)
                        metricCard("CPU","cpu",color:Palette.accent,badge:temperature(model.snapshot.temperatures.cpu)) {
                            metric(model.snapshot.cpu.map { String(format:"%.0f",$0) } ?? "—",unit:"%")
                            HistoryPlot(values:model.cpuHistory,color:Palette.accent,bars:true).frame(height:30)
                            Text((model.snapshot.cpu.map {$0<20 ? "Idle" : $0<70 ? "Active" : "Busy"} ?? "—")+(model.snapshot.loadAverages.first.map {String(format:" · Load %.1f",$0)} ?? "")).statusNote()
                        }.frame(width:unit)
                        metricCard("GPU","display",color:Color(red:0.78,green:0.61,blue:0.40),badge:temperature(model.snapshot.temperatures.gpu)) {
                            metric(model.snapshot.gpu.utilization.map {String(format:"%.0f",$0)} ?? "—",unit:"%")
                            HistoryPlot(values:model.gpuHistory,color:Color(red:0.78,green:0.61,blue:0.40),label:"GPU history, up to 60 samples").frame(height:30)
                            Text(model.snapshot.gpu.utilization.map {($0<10 ? "Idle" : $0<70 ? "Active" : "Busy")+" · "+model.snapshot.gpu.model} ?? "Unavailable").statusNote().help(model.snapshot.gpu.state)
                        }.frame(width:unit)
                        metricCard("MEMORY","memorychip",color:Color(red:0.83,green:0.73,blue:0.44),badge:pressureLabel) {
                            metric(model.snapshot.memoryTotal>0 ? String(format:"%.0f",memoryPercent) : "—",unit:"%")
                            HistoryPlot(values:model.memoryHistory,color:Color(red:0.84,green:0.74,blue:0.46)).frame(height:30)
                            Text(bytes(model.snapshot.memoryUsed)+" · "+bytes(model.snapshot.swapUsed)+" swap").statusNote()
                        }.frame(width:unit)
                    }.frame(height:(dashboardHeight-14)/2)
                    HStack(spacing:14) {
                        batteryCard.frame(width:unit*1.2)
                        metricCard("FREE SPACE","internaldrive",color:Color(red:0.44,green:0.65,blue:0.83),badge:bytes(model.snapshot.diskTotal)) {
                            metric(bytes(model.snapshot.diskFree),unit:"")
                            Capsule().fill(Palette.line).overlay(alignment:.leading) { Capsule().fill(LinearGradient(colors:[Palette.sage,Color(red:0.43,green:0.69,blue:0.53)],startPoint:.leading,endPoint:.trailing)).frame(maxWidth:.infinity,alignment:.leading).scaleEffect(x:diskUsed,y:1,anchor:.leading) }.frame(height:9).padding(.vertical,10)
                            Text(bytes(model.snapshot.diskTotal>=model.snapshot.diskFree ? model.snapshot.diskTotal-model.snapshot.diskFree : 0)+String(format:" used · %.0f%%",diskUsed*100)).statusNote()
                        }.frame(width:unit)
                        Button {showInterfaces=true} label:{metricCard("NETWORK","network",color:Color(red:0.40,green:0.69,blue:0.90),badge:connectionLabel) {
                            metric(primary.map {bytes(UInt64(max(0,$0.download+$0.upload)))} ?? "—",unit:"/s")
                            NetworkPlot(download:model.networkHistory,upload:model.networkUploadHistory).frame(height:30)
                            Text(primary.map {"↑ "+bytes(UInt64(max(0,$0.upload)))+" · ↓ "+bytes(UInt64(max(0,$0.download)))} ?? "Waiting for counters").statusNote()
                        }}.buttonStyle(.plain).handCursor().accessibilityLabel("Network interfaces").frame(width:unit)
                        metricCard("THERMAL","thermometer.medium",color:Palette.accent,badge:thermalLabel) {
                            HStack(spacing:14) {
                                temperatureMetric(model.snapshot.temperatures.cpu,label:"CPU")
                                temperatureMetric(model.snapshot.temperatures.gpu,label:"GPU")
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            HStack(spacing:4) {ForEach(0..<4) {index in Capsule().fill(index < (["Nominal":1,"Fair":2,"Serious":3,"Critical":4][model.snapshot.thermal] ?? 0) ? (model.snapshot.thermal=="Serious" || model.snapshot.thermal=="Critical" ? Palette.accent:Palette.sage):Palette.line)}}.frame(height:9).padding(.vertical,10).accessibilityLabel("Thermal state "+model.snapshot.thermal)
                            Text(model.snapshot.gpu.model+(model.snapshot.temperaturePeak.map {" · 5m peak "+temperature($0)} ?? "")).statusNote()
                        }.frame(width:unit)
                    }.frame(height:(dashboardHeight-14)/2)
                }
            }.frame(height:dashboardHeight)
            StatusProcessList().frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.task {await model.refreshAccessoryBatteries()}
        .popover(isPresented:$showBatteryDevices) {batteryDevices}
        .popover(isPresented:$showInputs) {healthDetails}
        .popover(isPresented:$showInterfaces) {interfaceDetails}
        .onChange(of:showInputs || showInterfaces || showBatteryDevices) {_,visible in if visible {model.dialogTokens.insert(dialogID)} else {model.dialogTokens.remove(dialogID)}}
        .onDisappear {model.dialogTokens.remove(dialogID)}
    }
    private var healthDetails:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text(health.title).font(.headline);Spacer();Button {showInputs=false} label:{Image(systemName:"xmark")}.buttonStyle(QuietIconStyle()).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close health details").focusable().focusEffectDisabled().focused($healthCloseFocused).onKeyPress(.escape) {showInputs=false;return .handled}}
            HStack {Text("Memory pressure");Spacer();Text(pressureLabel)}
            HStack {Text("Free storage");Spacer();Text(model.snapshot.diskTotal>0 ? String(format:"%.0f%%",Double(model.snapshot.diskFree)/Double(model.snapshot.diskTotal)*100):"—")}
            HStack {Text("Thermal state");Spacer();Text(model.snapshot.thermal=="Nominal" ? "Normal":model.snapshot.thermal)}
            Text(health.explanation).foregroundStyle(Palette.muted)
        }.font(.system(size:12)).padding(20).frame(width:350).bonsaiAppearance().task {await Task.yield();healthCloseFocused=true}
    }
    private var interfaceDetails:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Network interfaces").font(.headline);Spacer();Button {showInterfaces=false} label:{Image(systemName:"xmark")}.buttonStyle(QuietIconStyle()).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close network interfaces").focusable().focusEffectDisabled().focused($networkCloseFocused).onKeyPress(.escape) {showInterfaces=false;return .handled}}
            if model.snapshot.networks.isEmpty {Text("Waiting for a sample").foregroundStyle(Palette.muted)}
            ForEach(model.snapshot.networks,id:\.interface) {rate in HStack {Text(model.snapshot.networkNames[rate.interface] ?? NetworkConnectionLabels.fallback(rate.interface));Text(rate.interface).foregroundStyle(Palette.muted);Spacer();Text("↑ "+bytes(UInt64(max(0,rate.upload)))+"/s · ↓ "+bytes(UInt64(max(0,rate.download)))+"/s")}}
        }.font(.system(size:11)).padding(20).frame(width:390).bonsaiAppearance().task {await Task.yield();networkCloseFocused=true}
    }
    var healthCard:some View {
        Button {showInputs=true} label:{VStack(alignment:.leading,spacing:12) {
            HStack { Label("HEALTH",systemImage:"sun.max").font(.system(size:10,weight:.bold)).tracking(1).foregroundStyle(Color(red:0.83,green:0.65,blue:0.36));Spacer();SourceBadge(text:model.snapshot.gpu.model.replacingOccurrences(of:"Apple ",with:""));SourceBadge(text:"\(Int((Double(model.snapshot.memoryTotal)/1_073_741_824).rounded())) GB");SourceBadge(text:"macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)") }
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:10) { Text(health.title).font(.system(size:25,weight:.bold));Text(model.snapshot.health=="No pressure detected" ? "A healthy balance":model.snapshot.health).font(.system(size:11,weight:.medium)).foregroundStyle(Palette.muted) }.frame(maxWidth:.infinity,alignment:.leading)
                NatureIllustration(scene:.olive).frame(width:64,height:64).designElement("status.tree").accessibilityLabel(NatureScene.olive.name)
            }
            Spacer(minLength:0)
            HStack {Text("up \(Int(model.snapshot.uptime/86400))d \(Int(model.snapshot.uptime/3600)%24)h");Spacer();TimelineView(.periodic(from:.now,by:1)) {context in Text("\(Int(max(0,context.date.timeIntervalSince(model.snapshot.date))))s ago")}}.statusNote()
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).quietSurface(radius:16)}.buttonStyle(.plain).handCursor().accessibilityLabel("Health "+health.title).help(health.explanation).designElement("status.HEALTH")
    }
    private var batteryStatus:String {
        let b=model.snapshot.batteryDetails
        func duration(_ minutes:Int)->String {minutes>=60 ? "\(minutes/60)h \(minutes%60)m":"\(minutes)m"}
        if b.charging==true {return ["Charging",b.watts.map {String(format:"%.1f W",$0)},b.minutesToFull.map {duration($0)+" to full"}].compactMap {$0}.joined(separator:" · ")}
        if b.full {return "Fully charged"}
        if b.externalPower==true {return "On power · Not charging"}
        if b.externalPower==false {return [b.watts.map {String(format:"Discharge %.1f W",$0)} ?? "On battery",b.minutesRemaining.map {duration($0)+" left"}].compactMap {$0}.joined(separator:" · ")}
        return "—"
    }
    private var topDrain:ProcessGroup? {model.snapshot.processGroups.filter {($0.powerScore ?? 0)>0}.max {($0.powerScore ?? 0)<($1.powerScore ?? 0)}}
    var batteryCard:some View {
        metricCard("BATTERY",model.snapshot.batteryDetails.charging==true ? "battery.100percent.bolt":"battery.75percent",color:Palette.sage,badge:model.snapshot.batteryHealth.replacingOccurrences(of:" design capacity (registry estimate)",with:" Health")) {
            HStack(spacing:9) {
                metric(model.snapshot.battery.map {String(format:"%.0f",$0)} ?? "—",unit:"%")
                Spacer(minLength:2)
                Button {showBatteryDevices=true} label:{
                    HStack(spacing:8) {
                        BatteryLevelRing(name:"Mac",symbol:"laptopcomputer",level:model.snapshot.battery)
                        ForEach(Array(model.accessoryBatteries.prefix(2).enumerated()),id:\.offset) {_,device in BatteryLevelRing(name:device.0,symbol:accessorySymbol(device.0),level:Double(device.1))}
                        if model.accessoryBatteries.count>2 {Text("+\(model.accessoryBatteries.count-2)").font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted)}
                    }
                }.buttonStyle(.plain).handCursor().accessibilityLabel("Connected device batteries")
            }
            Text(batteryStatus).statusNote()
            Spacer(minLength:0)
            Text(topDrain.map {"Top Drain · "+$0.name} ?? "Top Drain · —").statusNote().help("Highest energy impact score, including app helpers.")
        }
    }
    private func accessorySymbol(_ name:String)->String {
        let name=name.lowercased()
        if name.contains("airpod") || name.contains("headphone") || name.contains("earbud") || name.contains("headset") {return "headphones"}
        if name.contains("mouse") {return "computermouse"}
        if name.contains("keyboard") {return "keyboard"}
        if name.contains("trackpad") {return "rectangle.and.hand.point.up.left"}
        if name.contains("controller") || name.contains("gamepad") {return "gamecontroller"}
        if name.contains("iphone") {return "iphone"}
        return "battery.75percent"
    }
    private var batteryDevices:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Batteries").font(.headline);Spacer();Button {showBatteryDevices=false} label:{Image(systemName:"xmark")}.buttonStyle(QuietIconStyle()).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close batteries")}
            HStack {Label("Mac",systemImage:"laptopcomputer");Spacer();Text(model.snapshot.battery.map {String(format:"%.0f%%",$0)} ?? "—")}
            Text(batteryStatus).foregroundStyle(Palette.muted)
            ForEach(Array(model.accessoryBatteries.enumerated()),id:\.offset) {_,device in HStack {Label(device.0,systemImage:accessorySymbol(device.0));Spacer();Text("\(device.1)%")}}
            if model.accessoryBatteries.isEmpty {Text("No connected-device readings").foregroundStyle(Palette.muted)}
        }.font(.system(size:12)).padding(20).frame(width:320).bonsaiAppearance()
    }
    private func temperatureMetric(_ value:Double?,label:String)->some View {
        HStack(alignment:.firstTextBaseline,spacing:4) {Text(temperature(value)).font(.system(size:22,weight:.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7);Text(label).font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted)}
    }
    func metric(_ value:String,unit:String) -> some View { HStack(alignment:.firstTextBaseline,spacing:4) { Text(value).font(.system(size:25,weight:.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.60).contentTransition(.numericText()).animation(reduceMotion ? nil : .easeInOut(duration:0.22),value:value);if !unit.isEmpty { Text(unit).font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted) } }.frame(maxWidth:.infinity,alignment:.leading) }
    func metricCard<Content:View>(_ title:String,_ symbol:String,color:Color,badge:String,@ViewBuilder content:() -> Content) -> some View {
        VStack(alignment:.leading,spacing:12) { HStack(spacing:7) { Image(systemName:symbol).foregroundStyle(color);Text(title).font(.system(size:10,weight:.bold)).tracking(1).foregroundStyle(Palette.text.opacity(0.72));Spacer(minLength:0);if !badge.isEmpty { SourceBadge(text:badge).lineLimit(1) } };content() }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).quietSurface(radius:16).designElement("status."+title)
    }
}

struct HistoryPlot:View {
    var values:[Double];var color:Color;var bars=false;var label:String?=nil
    var body:some View { Canvas { context,size in
        guard !values.isEmpty else { return };let ceiling=max(100,values.max() ?? 1)
        if bars { let visible=Array(values.suffix(14));let width=size.width/CGFloat(visible.count);for (i,v) in visible.enumerated() { let h=max(2,size.height*min(1,max(0,v/ceiling)));let rect=CGRect(x:CGFloat(i)*width,y:size.height-h,width:max(1,width-3),height:h);context.fill(Path(roundedRect:rect,cornerRadius:1),with:.linearGradient(Gradient(colors:[color,color.opacity(0.30)]),startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:0,y:size.height))) } }
        else { var line=Path();for (i,v) in values.enumerated() { let point=CGPoint(x:size.width*CGFloat(i)/CGFloat(max(1,values.count-1)),y:size.height*(1-min(1,max(0,v/ceiling))));if i==0 { line.move(to:point) } else { line.addLine(to:point) } };var fill=line;fill.addLine(to:CGPoint(x:size.width,y:size.height));fill.addLine(to:CGPoint(x:0,y:size.height));fill.closeSubpath();context.fill(fill,with:.linearGradient(Gradient(colors:[color.opacity(0.22),color.opacity(0)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)));context.stroke(line,with:.color(color),lineWidth:1.3) }
    }.accessibilityLabel(label ?? (bars ? "CPU history, up to 14 samples" : "Memory history, up to 60 samples")) }
}
struct NetworkPlot:View {
    var download:[Double];var upload:[Double]
    var body:some View { Canvas { context,size in
        let ceiling=max(1,(download+upload).max() ?? 1)
        for (values,color,direction) in [(download,Color(red:0.34,green:0.68,blue:0.93),1.0),(upload,Palette.accent,-1.0)] {
            var path=Path();for (i,v) in values.enumerated() { let point=CGPoint(x:size.width*CGFloat(i)/CGFloat(max(1,values.count-1)),y:size.height/2+direction*size.height/2*min(1,max(0,v/ceiling)));if i==0 { path.move(to:point) } else { path.addLine(to:point) } };context.stroke(path,with:.color(color),lineWidth:1)
        }
    }.accessibilityLabel("Download and upload history, up to 60 samples") }
}
extension View { func statusNote() -> some View { self.font(.system(size:11,weight:.medium)).foregroundStyle(Palette.muted).lineLimit(2) } }

private struct BatteryLevelRing:View {
    let name:String;let symbol:String;let level:Double?
    private var color:Color {(level ?? 100)<=20 ? Palette.accent:Palette.sage}
    var body:some View {
        ZStack {
            Circle().stroke(Palette.line,lineWidth:3)
            Circle().trim(from:0,to:CGFloat(min(100,max(0,level ?? 0))/100)).stroke(color,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))
            Image(systemName:symbol).font(.system(size:13)).foregroundStyle(Palette.muted)
        }.frame(width:34,height:34).help(name+": "+(level.map {String(format:"%.0f%%",$0)} ?? "—")).accessibilityLabel(name+" battery").accessibilityValue(level.map {String(format:"%.0f%%",$0)} ?? "Unavailable")
    }
}
