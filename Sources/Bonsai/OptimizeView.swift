import SwiftUI
import AppKit
import BonsaiCore

struct OptimizeView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var reviewing=false
    private var running:Bool {model.busy && model.operationKind=="maintenance"}
    private var summary:MaintenanceSummary {MaintenanceSummary(tasks:model.maintenanceTasks,outcomes:model.maintenanceOutcomes)}
    var body:some View {
        Group {
            if model.maintenanceScreen == .details {
                OptimizeDetailsView(review:{reviewing=true})
                    .transition(.opacity.combined(with:.offset(y:reduceMotion ? 0 : 10)))
            } else {hero.transition(.opacity)}
        }.animation(reduceMotion ? nil : .easeOut(duration:0.28),value:model.maintenanceScreen)
        .sheet(isPresented:$reviewing) {MaintenanceReviewSheet().environmentObject(model).compactInterface()}
    }
    private var hero:some View {
        GeometryReader {geometry in
            let h=geometry.size.height
            let art=BonsaiActivityMotion.portraitSize(height:h,checklist:running)
            let complete=model.maintenanceScreen == .complete
            BonsaiScrollView {
                VStack(spacing:20) {
                    VStack(spacing:8) {
                        Group {if running {BonsaiActivityPortrait(scene:.maple)} else {NatureIllustration(scene:.maple)}}.frame(width:art,height:art).designElement("optimize.tree")
                        Text(NatureScene.maple.name).font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(Palette.muted).accessibilityLabel(NatureScene.maple.name+", "+NatureScene.maple.botanicalName).designElement("optimize.caption")
                    }
                    VStack(spacing:12) {
                        if running {
                            Text("Restoring a little balance").font(.system(size:25,weight:.semibold,design:.rounded))
                            Text(model.progress).font(.system(size:12)).foregroundStyle(Palette.muted).lineLimit(2).truncationMode(.middle)
                        } else if complete {
                            Text(summary.headline(cancelled:model.maintenanceCancelled)).font(.system(size:27,weight:.semibold,design:.rounded))
                            Text(summary.label).font(.system(size:12)).foregroundStyle(Palette.muted)
                        } else {
                            Text(NatureScene.maple.verse).font(.system(size:16,weight:.semibold,design:.serif)).lineSpacing(6).foregroundStyle(Palette.muted)
                        }
                    }.multilineTextAlignment(.center).frame(maxWidth:560).fixedSize(horizontal:false,vertical:true).designElement("optimize.title")
                    if running {
                        progressChecklist(maxRows:BonsaiActivityMotion.checklistRows(height:h)).frame(width:min(430,geometry.size.width-72))
                        Button("Cancel maintenance",action:model.cancel).buttonStyle(SoftCapsuleStyle()).handCursor().keyboardShortcut(.cancelAction)
                    } else {
                        VStack(spacing:14) {
                            if complete {
                                Button {model.maintenanceScreen = .details} label:{Text("Review results").frame(width:236,height:38)}.buttonStyle(OptimizeHeroButtonStyle()).handCursor().bonsaiDefaultAction()
                                Button {model.maintenanceScreen = .overview} label:{Label("Back to balance",systemImage:"arrow.left").frame(width:212)}.buttonStyle(BalanceReturnButtonStyle()).handCursor()
                            } else {
                                Button(action:model.optimize) {Text("Optimize").frame(width:236,height:38)}.buttonStyle(OptimizeHeroButtonStyle()).handCursor().bonsaiDefaultAction().disabled(model.busy).designElement("optimize.action").help("Refresh Finder caches, compact eligible inactive-app databases, and check Spotlight, background services and sleep activity. Starts immediately; administrator tasks are skipped.")
                                if model.maintenanceDate != nil {Button("Last results") {model.maintenanceScreen = .details}.buttonStyle(QuietTextStyle()).handCursor()}
                            }
                        }
                    }
                }.padding(.vertical,20).frame(maxWidth:.infinity).frame(minHeight:h)
            }.overlay(alignment:.bottomTrailing) {
                if !running {Button {reviewing=true} label:{Image(systemName:"slider.horizontal.3").font(.system(size:14)).frame(width:30,height:30)}.buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy).accessibilityLabel("Maintenance options").padding(18)}
            }
        }
    }
    private var recentTasks:[MaintenanceTask] {
        let index=model.maintenanceTasks.firstIndex {$0.id==model.maintenanceActive} ?? 0
        return Array(model.maintenanceTasks.prefix(index+1).suffix(4))
    }
    private func progressChecklist(maxRows:Int)->some View {
        VStack(alignment:.leading,spacing:10) {
            Text(model.maintenanceTasks.first {$0.id==model.maintenanceActive}?.group ?? "Preparing").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(Palette.muted)
            ForEach(Array(recentTasks.suffix(maxRows))) {task in
                let outcome=model.maintenanceOutcomes.first {$0.path==task.preview}
                HStack(spacing:10) {
                    if outcome==nil && model.maintenanceActive==task.id {BonsaiActivityGlyph(size:16).frame(width:16)}
                    else {Image(systemName:["Completed","Unchanged"].contains(outcome?.status ?? "") ? "checkmark" : outcome==nil ? "circle" : "minus.circle").frame(width:16).foregroundStyle(Palette.sage)}
                    Text(task.title).font(.system(size:11,weight:.medium,design:.monospaced)).lineLimit(1);Spacer(minLength:0)
                }.accessibilityElement(children:.combine).accessibilityLabel(task.title+", "+(outcome?.status ?? (model.maintenanceActive==task.id ? "Running" : "Waiting")))
            }
        }.padding(.horizontal,18).padding(.vertical,14).bonsaiGlass(radius:18)
            .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:model.maintenanceActive)
    }
}
private struct OptimizeHeroButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:14,weight:.semibold))
            .foregroundStyle(enabled ? Palette.ink : Palette.muted)
            .padding(.horizontal,12).padding(.vertical,4)
            .background(enabled ? Color.white.opacity(1) : Palette.line,in:Capsule())
            .overlay(Capsule().stroke(.white.opacity(enabled ? 0.45 : 0)))
            .shadow(color:Palette.sage.opacity(enabled ? 0.12 : 0),radius:18,y:3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:configuration.isPressed)
    }
}

private struct MaintenanceReviewSheet:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    private var plan:[MaintenanceTask] {MaintenanceRunner.plan(selected:model.maintenanceSelection)}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text("Optimize your Mac").font(.system(size:24,weight:.semibold,design:.rounded));Spacer();Button {dismiss()} label:{Image(systemName:"xmark.circle.fill").font(.system(size:20)).foregroundStyle(Palette.muted)}.buttonStyle(.plain).handCursor().accessibilityLabel("Close maintenance review").keyboardShortcut(.cancelAction)}
            BonsaiScrollView(edgeInset:26) {
                VStack(alignment:.leading,spacing:18) {
                    ForEach(MaintenanceTask.groups,id:\.self) {group in
                        VStack(alignment:.leading,spacing:0) {
                            Text(group).font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted).padding(.bottom,8)
                            ForEach(MaintenanceTask.catalog.filter {$0.group==group}) {task in MaintenanceReviewRow(task:task,selection:$model.maintenanceSelection)}
                        }
                    }
                }
            }
            HStack(spacing:12) {
                Text("\(plan.count) selected").font(.system(size:12,weight:.semibold))
                Button("Recommended") {model.maintenanceSelection=Set(MaintenanceTask.catalog.filter {$0.recommended && $0.available}.map(\.id))}.buttonStyle(QuietTextStyle()).handCursor()
                Spacer();Button("Run \(plan.count) task\(plan.count==1 ? "" : "s")") {let tasks=plan;dismiss();model.runMaintenance(tasks)}.bonsaiPrimary().handCursor().disabled(plan.isEmpty || model.busy || plan.contains {!$0.available})
            }
        }.padding(26).frame(width:650,height:570).background(BonsaiBackground(page:.optimize)).bonsaiAppearance()
    }
}
private struct MaintenanceReviewRow:View {
    let task:MaintenanceTask
    @Binding var selection:Set<String>
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Toggle(isOn:Binding(get:{selection.contains(task.id)},set:{if $0 {selection.insert(task.id)} else {selection.remove(task.id)}})) {
                HStack(spacing:10) {
                    Text(task.title).font(.system(size:13,weight:.medium,design:.rounded))
                    Spacer(minLength:8)
                }
            }.toggleStyle(MaintenanceSelectionStyle()).handCursor().disabled(!task.available)
            if !task.available {Text("Unavailable: system command is missing.").font(.system(size:11)).foregroundStyle(Palette.accent)}
            Rectangle().fill(Palette.line.opacity(0.55)).frame(height:0.5)
        }.padding(.vertical,1)
    }
}

private struct MaintenanceSelectionStyle:ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        Button {configuration.isOn.toggle()} label: {
            HStack(spacing:12) {
                RoundedRectangle(cornerRadius:5).fill(configuration.isOn ? Palette.accent.opacity(0.8) : Palette.text.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(configuration.isOn ? Palette.accent.opacity(0.3) : Palette.muted.opacity(0.28)))
                    .overlay {if configuration.isOn {Image(systemName:"checkmark") .font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.ink)}}
                    .frame(width:18,height:18).accessibilityHidden(true)
                configuration.label
            }.padding(.horizontal,6).frame(minHeight:40).frame(maxWidth:.infinity)
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).bonsaiListHover().opacity(enabled ? 1:0.4)
            .animation(reduceMotion ? nil:.easeInOut(duration:0.16),value:configuration.isOn)
            .accessibilityRepresentation {Toggle(isOn:configuration.$isOn) {configuration.label}.toggleStyle(.checkbox)}
    }
}

private struct OptimizeDetailsView:View {
    @EnvironmentObject var model:AppModel
    var review:()->Void
    private var summary:MaintenanceSummary {MaintenanceSummary(tasks:model.maintenanceTasks,outcomes:model.maintenanceOutcomes)}
    var body:some View {
        GeometryReader {geometry in
            let rows=max(1,(model.maintenanceOutcomes.count+1)/2)
            let rowHeight=min(40,max(24,(geometry.size.height-270)/CGFloat(rows)))
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:12) {
                    NatureIllustration(scene:.maple).frame(width:56,height:56).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Optimize details").font(.system(size:24,weight:.semibold,design:.rounded))
                        Text(model.maintenanceDate.map {$0.formatted(date:.abbreviated,time:.shortened)} ?? "Your maintenance report").font(.system(size:10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button {model.maintenanceScreen = .complete} label:{Image(systemName:"xmark").font(.system(size:12,weight:.semibold)).frame(width:30,height:30).background(Palette.card,in:Circle())}.buttonStyle(.plain).handCursor().accessibilityLabel("Close optimize details")
                }
                HStack(spacing:10) {
                    metric("refreshed & checked",count:summary.completed,symbol:"leaf",color:Palette.sage)
                    metric("healthy",count:summary.unchanged,symbol:"checkmark.seal",color:Palette.sage)
                    metric("need attention",count:summary.attention,symbol:"exclamationmark.circle",color:Palette.accent)
                    metric("skipped",count:summary.skipped+summary.unavailable,symbol:"minus.circle",color:Palette.muted)
                    Spacer(minLength:0)
                }
                HStack(spacing:18) {
                    Text("Maintenance tasks").font(.system(size:11,weight:.semibold)).foregroundStyle(Palette.muted)
                    Spacer();Text("Click a task for its output").font(.system(size:10)).foregroundStyle(Palette.muted)
                }
                if model.maintenanceOutcomes.isEmpty {Text("No maintenance results yet. Choose tasks to begin.").foregroundStyle(Palette.muted)}
                else {
                    HStack(alignment:.top,spacing:14) {
                        column(Array(model.maintenanceOutcomes.prefix(rows)),rowHeight:rowHeight)
                        column(Array(model.maintenanceOutcomes.dropFirst(rows)),rowHeight:rowHeight)
                    }.frame(maxWidth:.infinity,alignment:.top)
                }
                Spacer(minLength:0)
                HStack(spacing:16) {
                    Button("Copy summary") {NSPasteboard.general.clearContents();NSPasteboard.general.setString("Bonsai maintenance · "+summary.label+"\n"+model.maintenanceOutcomes.map {$0.title+": "+$0.status}.joined(separator:"\n"),forType:.string)}.buttonStyle(QuietTextStyle()).handCursor().disabled(model.maintenanceOutcomes.isEmpty)
                    if summary.attention>0 {Button("Review unfinished") {model.maintenanceSelection=Set(model.maintenanceTasks.filter {t in model.maintenanceOutcomes.contains {$0.path==t.preview && !["Completed","Unchanged","Skipped","Unavailable"].contains($0.status)}}.map(\.id));review()}.buttonStyle(QuietTextStyle()).handCursor().disabled(model.busy)}
                    Spacer();Button("Choose tasks",action:review).buttonStyle(SoftCapsuleStyle()).handCursor().disabled(model.busy)
                }
            }.padding(.horizontal,26).padding(.top,16).padding(.bottom,16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }
    }
    private func metric(_ title:String,count:Int,symbol:String,color:Color)->some View {
        HStack(spacing:6) {Image(systemName:symbol).foregroundStyle(color);Text("\(count)").fontWeight(.semibold).monospacedDigit();Text(title).foregroundStyle(Palette.muted)}.font(.system(size:10)).padding(.horizontal,10).padding(.vertical,7).background(Palette.card,in:Capsule()).accessibilityElement(children:.combine)
    }
    private func column(_ outcomes:[ItemOutcome],rowHeight:CGFloat)->some View {
        VStack(spacing:0) {
            ForEach(outcomes) {item in MaintenanceOutcomeRow(item:item,task:model.maintenanceTasks.first {$0.preview==item.path},height:rowHeight)}
        }.padding(10).frame(maxWidth:.infinity,alignment:.top).bonsaiListSurface(radius:16)
    }
}
private struct MaintenanceOutcomeRow:View {
    @EnvironmentObject private var model:AppModel
    let item:ItemOutcome
    let task:MaintenanceTask?
    var height:CGFloat=30
    @ViewState private var expanded=false
    @ViewState private var dialogID=UUID()
    @ViewState private var hovered=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var completed:Bool {["Completed","Unchanged"].contains(item.status)}
    private var status:String {item.status=="Unchanged" ? "Healthy" : completed ? (task?.readOnly==true ? "Checked" : task==nil ? "Completed" : "Refreshed") : item.status=="Needs attention" ? "Attention" : item.status=="Needs access" ? "Access" : item.status}
    private var color:Color {completed ? Palette.sage : ["Skipped","Unavailable"].contains(item.status) ? Palette.muted : Palette.accent}
    var body:some View {
        Button {expanded=true} label:{
            HStack(spacing:8) {
                Image(systemName:completed ? "checkmark" : ["Skipped","Unavailable"].contains(item.status) ? "minus" : "exclamationmark.circle").foregroundStyle(color).frame(width:13).accessibilityHidden(true)
                Text(item.title).font(.system(size:12,weight:.medium)).lineLimit(1).minimumScaleFactor(0.85).frame(maxWidth:.infinity,alignment:.leading)
                Text(status).font(.system(size:10,weight:.medium)).foregroundStyle(color).padding(.horizontal,6).padding(.vertical,3).background(color.opacity(0.08),in:Capsule())
                Image(systemName:"chevron.right").font(.system(size:8)).foregroundStyle(Palette.muted).accessibilityHidden(true)
            }.padding(.horizontal,8).frame(height:height).contentShape(Rectangle())
        }.buttonStyle(.plain).handCursor().accessibilityLabel(item.title+", "+status+", show output").accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .background(Palette.text.opacity(hovered ? 0.055 : 0),in:RoundedRectangle(cornerRadius:9))
            .onHover {value in withAnimation(reduceMotion ? nil : .easeOut(duration:0.12)) {hovered=value}}
            .onChange(of:expanded) {_,value in if value {model.dialogTokens.insert(dialogID)} else {model.dialogTokens.remove(dialogID)}}
            .onDisappear {hovered=false;model.dialogTokens.remove(dialogID)}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) {_ in hovered=false}
            .popover(isPresented:$expanded) {
                VStack(alignment:.leading,spacing:14) {
                    HStack(alignment:.top) {Text(item.title).font(.system(size:15,weight:.semibold)).lineLimit(nil).fixedSize(horizontal:false,vertical:true);Spacer();Button {expanded=false} label:{Image(systemName:"xmark").frame(width:24,height:24)}.buttonStyle(.plain).handCursor().accessibilityLabel("Close task output").keyboardShortcut(.cancelAction)}
                    BonsaiScrollView(edgeInset:20) {
                        VStack(alignment:.leading,spacing:14) {
                            Text(item.status).font(.system(size:12,weight:.medium)).foregroundStyle(color)
                            if let task {Text(task.explanation).font(.system(size:11)).foregroundStyle(Palette.muted)}
                            Text(item.path).font(.system(size:9,design:.monospaced))
                            Text(item.detail).font(.system(size:10,design:.monospaced))
                        }.lineLimit(nil).fixedSize(horizontal:false,vertical:true)
                            .frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                            .padding(.bottom,4)
                    }.frame(height:260)
                }.padding(20).frame(width:420).background(BonsaiBackground(page:.optimize)).bonsaiAppearance().compactInterface()
            }
    }
}
