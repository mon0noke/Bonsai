import SwiftUI
import AppKit
import BonsaiCore

struct DoctorView:View {
    @EnvironmentObject private var model:AppModel
    var onClose:()->Void
    @ViewState private var report:DoctorReport?
    @ViewState private var refresh=0
    @ViewState private var copied=false
    @ViewState private var checking=false
    var body:some View {
        VStack(spacing:18) {
            UtilityHeader(title:"Doctor",subtitle:"A snapshot of your Mac and Bonsai. Copy it when reporting an issue.",onClose:onClose)
            BonsaiScrollView(edgeInset:24) {
                VStack(alignment:.leading,spacing:12) {
                    if let report {
                        VStack(alignment:.leading,spacing:10) {
                            HStack {Text("Detected issues").font(.system(size:13,weight:.bold));Spacer();Button("Go to Status") {onClose();model.page = .status}.buttonStyle(QuietTextStyle()).handCursor()}
                            if report.issues.isEmpty {Label("No issue detected in this snapshot",systemImage:"checkmark.circle").foregroundStyle(Palette.sage)}
                            else {ForEach(Array(report.issues.enumerated()),id:\.offset) {_,issue in Label(issue,systemImage:"exclamationmark.circle").foregroundStyle(Palette.accent)}}
                        }.font(.system(size:12)).padding(16).frame(maxWidth:.infinity,alignment:.leading).bonsaiListSurface(radius:14)
                        ForEach(report.sections) {section in
                            VStack(alignment:.leading,spacing:10) {
                                Text(section.title).font(.system(size:13,weight:.bold)).padding(.bottom,3)
                                ForEach(Array(section.rows.enumerated()),id:\.offset) {_,row in
                                    HStack(alignment:.top,spacing:18) {Text(row.label).foregroundStyle(Palette.muted).frame(width:125,alignment:.leading);Text(row.value).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}.font(.system(size:11)).fixedSize(horizontal:false,vertical:true)
                                }
                            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).bonsaiListSurface(radius:14)
                        }
                        Text("Local report only. Folder probes do not establish the macOS permission switch state. Health uses the listed inputs; unavailable sensors are not estimated.").font(.system(size:10)).foregroundStyle(Palette.muted)
                    } else {BonsaiActivityStrip(title:"Reading your Mac",detail:"Collecting a read-only snapshot")}
                }.padding(.trailing,4)
            }
            HStack {
                Button {refresh+=1;copied=false} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(QuietIconStyle()).handCursor().accessibilityLabel("Refresh Doctor report").disabled(checking)
                if let report {Text(report.date.formatted(date:.omitted,time:.shortened)).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted)}
                Spacer()
                Button(copied ? "Copied":"Copy Report") {guard let report else {return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(report.text,forType:.string);copied=true}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(report==nil || checking)
            }
        }.padding(24).task(id:refresh) {await capture()}.accessibilityElement(children:.contain).accessibilityLabel("Doctor")
    }
    @MainActor private func capture() async {
        checking=true
        let sample=model.snapshot
        let environment=[DoctorRow("macOS",ProcessInfo.processInfo.operatingSystemVersionString),DoctorRow("Chip",DoctorReport.hardware("machdep.cpu.brand_string")),DoctorRow("Model",DoctorReport.hardware("hw.model")),DoctorRow("Architecture","arm64 · native Apple Silicon"),DoctorRow("Locale",Locale.current.identifier),DoctorRow("Displays",NSScreen.screens.map {"\(Int($0.frame.width))×\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x"}.joined(separator:" · "))]
        let configuration=[DoctorRow("Removal","Move to Trash · permanent emptying reviewed separately"),DoctorRow("Protected items","\(model.exclusions.count) custom paths"),DoctorRow("Automatic update checks",model.updateStore.automatic ? "On":"Off"),DoctorRow("Menu bar",UserDefaults.standard.object(forKey:"menuBarVisible") as? Bool == false ? "Hidden":"Shown"),DoctorRow("Keep Screen On",model.keepAwake ? "On":"Off"),DoctorRow("License","GPL-3.0")]
        let runtime=[DoctorRow("Bonsai",(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown")+" ("+(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "Unknown")+")"),DoctorRow("Bonsai backend",String(ProtectionBackend.revision.prefix(12))),DoctorRow("Operation",model.busy ? model.operationKind:"Idle"),DoctorRow("Local activity","\(model.history.count) retained operations"),DoctorRow("Network privacy","Update metadata only with consent; no telemetry upload")]
        let result=await Task.detached(priority:.utility) {DoctorReport.make(snapshot:sample,access:FileAccess.check(),environment:environment,configuration:configuration,runtime:runtime)}.value
        guard !Task.isCancelled else {return}
        report=result;checking=false
    }
}
