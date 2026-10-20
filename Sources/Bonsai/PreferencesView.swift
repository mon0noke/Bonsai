import SwiftUI
import AppKit
import ServiceManagement
import ApplicationServices
import BonsaiCore

private enum SettingsColors {
    static let sakura=Color(nsColor:Palette.adaptive("SettingsSakura",light:NSColor(srgbRed:0.63,green:0.29,blue:0.39,alpha:1),dark:NSColor(srgbRed:0.91,green:0.62,blue:0.69,alpha:1)))
}

struct PreferencesView:View {
    @EnvironmentObject private var model:AppModel
    var onClose:()->Void
    @AppStorage("notificationsEnabled") private var notificationsEnabled=true
    @AppStorage("appearance") private var appearance=BonsaiAppearance.light.rawValue
    @AppStorage("watchTrashApps") private var watchTrash=false
    @AppStorage("selectionDefault") private var defaults="Recommended"
    @AppStorage("menuBarVisible") private var menuVisible=true
    @AppStorage("menuBarDisplay") private var menuDisplay="Both"
    @AppStorage("cleanScreenDuration") private var screenDuration=60
    @AppStorage("menuBarOnly") private var menuOnly=false
    @AppStorage("swapMenuClicks") private var swapClicks=false
    @AppStorage("quitBehavior") private var quitBehavior="Quit Bonsai"
    @AppStorage("awakeBehavior") private var awakeBehavior=AwakeBehavior.screenAndWork.rawValue
    @AppStorage("awakeIcon") private var awakeIcon=true
    @AppStorage("cacheRemoval") private var cacheRemoval=CacheRemovalMode.trash.rawValue
    @AppStorage("temperatureUnit") private var temperatureUnit=TemperatureUnit.celsius.rawValue
    @AppStorage("publicCaskCatalogConsent") private var publicCatalogConsent=false
    @ViewState private var tab="General"
    @ViewState private var hardware=false
    @ViewState private var inputProtection=AXIsProcessTrustedWithOptions(nil)
    @ViewState private var protectedItems=false
    @ViewState private var access:FileAccessReport?
    @ViewState private var loginState=SMAppService.mainApp.status
    @ViewState private var loginError=""
    @ViewState private var accessRefresh=0
    @ViewState private var inputChecked=false
    var body:some View {
        VStack(spacing:16) {
            HStack(spacing:12) {
                if !protectedItems && !hardware {
                    SoftwareTabs(selection:$tab,accessibilityTitle:"Settings section",compact:true,tint:Palette.muted,neutralSelection:true,roomy:true,fitLabels:true,tabs:[("General",""),("Tools",""),("Menu Bar",""),("Notifications","")]).designElement("settings.tabs")
                } else {
                    Text(protectedItems ? "Protected items":"Hardware access").font(.system(size:18,weight:.semibold)).designElement("settings.title")
                }
                HStack {
                    Spacer()
                    Button(action:onClose) {Image(systemName:"xmark").font(.system(size:12,weight:.semibold))}
                        .buttonStyle(QuietIconStyle()).environment(\.bonsaiControlTint,Palette.muted).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close Settings")
                }
            }.frame(height:42).padding(.bottom,2)

            if protectedItems {protection}
            else if hardware {hardwareDetails}
            else {
                SettingsScrollView {
                    VStack(spacing:0) {
                        if tab=="General" {general}
                        else if tab=="Tools" {tools}
                        else if tab=="Menu Bar" {menu}
                        else {notifications}
                    }.padding(.horizontal,2).frame(maxWidth:.infinity,alignment:.leading)
                }
                Spacer(minLength:0)

            }
        }.padding(20)
        .background(SettingsColors.sakura.opacity(0.055),in:RoundedRectangle(cornerRadius:26,style:.continuous))
        .environment(\.bonsaiControlTint,SettingsColors.sakura)
        .task(id:accessRefresh) {
            let report=await Task.detached(priority:.utility) {FileAccess.check()}.value
            guard !Task.isCancelled else {return}
            access=report;loginState=SMAppService.mainApp.status
            await model.alerts.refreshAuthorization()
            await model.refreshTrashWatch()
        }
        // Lightweight trust checks only while Settings is mounted, including while
        // System Settings is frontmost. Cancellation stops the loop on dismissal.
        .task {
            while !Task.isCancelled {
                refreshInputProtection()
                do {try await Task.sleep(for:.seconds(2))} catch {return}
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) {_ in
            refreshInputProtection();accessRefresh += 1
        }
        .accessibilityElement(children:.contain).accessibilityLabel("Settings")
    }
    private var general:some View {
        Group {
            SettingRow("Appearance",detail:"Light, dark or match your Mac.") {
                SettingChoice(label:"Appearance",selection:$appearance,options:BonsaiAppearance.allCases.map {($0.rawValue,$0.title)})
            }
            SettingRow("Full Disk Access",detail:access?.summary ?? "Checking access…") {
                if access?.accessConfirmed == true {
                    Label("Granted",systemImage:"checkmark.circle.fill").font(.system(size:12,weight:.semibold)).foregroundStyle(SettingsColors.sakura)
                        .help("Protected directory access verified. macOS does not expose its Full Disk Access switch directly.")
                } else {
                    Button("Grant Access") {model.settings()}.buttonStyle(SettingButtonStyle()).handCursor()
                }
            }
            SettingRow("Clean Screen Protection",detail:inputProtection ? "Keyboard protection enabled. Escape exits." : inputChecked ? "Still unavailable? Restart Bonsai, or re-add it in macOS settings." : "Allow Accessibility to block system keys.") {
                if inputProtection {
                    Label("Enabled",systemImage:"checkmark.circle.fill")
                        .font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(SettingsColors.sakura)
                } else {
                    HStack(spacing:8) {
                        Button("Fix") {openSettings("Privacy_Accessibility")}.buttonStyle(SettingButtonStyle()).handCursor()
                        Button("Check") {refreshInputProtection();inputChecked=true}.buttonStyle(SettingButtonStyle()).handCursor()
                    }
                }
            }
            SettingRow("Launch at Login",detail:loginDescription) {
                Toggle("Launch Bonsai at Login",isOn:Binding(get:{loginState == .enabled},set:{value in changeLogin(value)})).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor()
            }
            if !loginError.isEmpty {Text(loginError).font(.system(size:11)).foregroundStyle(Palette.accent).padding(.vertical,8).textSelection(.enabled)}
            if loginState == .requiresApproval {Button("Fix") {SMAppService.openSystemSettingsLoginItems()}.buttonStyle(SettingButtonStyle()).handCursor().help("Open Login Items to approve Bonsai").frame(maxWidth:.infinity,alignment:.trailing).padding(.bottom,8)}
            SettingRow("Menu Bar Only",detail:"Hide the Dock icon when the window closes.") {Toggle("Menu Bar Only",isOn:$menuOnly).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor().disabled(!menuVisible)}
            SettingRow("License",detail:"GPL-3.0. No activation required.") {EmptyView()}
            SettingRow("Automatic Update Checks",detail:"Check for updates without installing them.") {
                Toggle("Automatic update checks",isOn:Binding(get:{model.updateStore.automatic},set:{model.updateStore.automatic=$0;if $0 && model.softwareTab=="Updates" {model.checkUpdates()}})).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor()
            }
            SettingRow("Public Homebrew Catalog",detail:"Send package names to formulae.brew.sh to check updates.") {
                Toggle("Check public Homebrew catalog",isOn:$publicCatalogConsent).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor().onChange(of:publicCatalogConsent) {_,value in model.updateStore.cancel();if value && model.softwareTab=="Updates" {model.checkUpdates()}}
            }
        }
    }
    private var tools:some View {
        Group {
            SettingRow("Protected Items",detail:"\(model.exclusions.count) folders excluded from cleaning.") {Button("Manage") {protectedItems=true}.buttonStyle(SettingButtonStyle()).handCursor()}
            SettingRow("Clean Selection",detail:"App data and models stay unchecked.") {
                SettingChoice(label:"Clean selection defaults",selection:$defaults,options:[("Recommended","Recommended"),("Nothing selected","Nothing"),("Low-risk logs","Logs")])
            }
            SettingRow("Cache Removal",detail:"Choose how caches are removed.") {
                SettingChoice(label:"Cache removal",selection:$cacheRemoval,options:[(CacheRemovalMode.permanent.rawValue,"Permanently"),(CacheRemovalMode.trash.rawValue,"Move to Trash")])
            }
            SettingRow("App Leftover Notices",detail:"Find leftover files after trashing apps.") {Toggle("Watch for apps moved to Trash",isOn:$watchTrash).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor()}
            if watchTrash && !model.trashWatchNote.isEmpty {
                HStack(alignment:.center,spacing:12) {
                    Text(model.trashWatchNote).font(.system(size:12,design:.rounded)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                    if model.trashWatchNeedsAccess {Button("Fix") {model.settings()}.buttonStyle(SettingButtonStyle()).handCursor().help("Open Full Disk Access for App Leftover Notices")}
                }.padding(.vertical,12)
            }
            SettingRow("Awake Shortcut",detail:"Toggle Keep Screen On from any app.") {ShortcutSetting(key:"awakeShortcut")}
            SettingRow("Awake Behavior",detail:"Prevent idle sleep. Closing the lid still sleeps.") {
                SettingChoice(label:"Keep Screen On behavior",selection:$awakeBehavior,options:AwakeBehavior.allCases.map {($0.rawValue,$0.rawValue)}).onChange(of:awakeBehavior) {_,_ in if model.keepAwake {let remaining=model.awakeDeadline?.timeIntervalSinceNow;model.awakeFor(remaining)}}
            }
            SettingRow("Keep Screen On Icon",detail:"Show a coffee cup while Awake is on.") {Toggle("Keep Screen On Icon",isOn:$awakeIcon).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor()}
            SettingRow("Clean Screen Shortcut",detail:"Toggle screen cleaning. Escape exits.") {ShortcutSetting(key:"screenShortcut")}
            SettingRow("Clean Screen Duration",detail:"Auto-exit time. Escape exits sooner.") {
                SettingChoice(label:"Clean screen duration",selection:$screenDuration,options:[(60,"1 minute"),(120,"2 minutes"),(300,"5 minutes")])
            }
            SettingRow("Battery Charge Limit",detail:"Open your Mac’s charging controls.") {Button("Battery Settings") {model.open(URL(string:"x-apple.systempreferences:com.apple.Battery-Settings.extension")!)}.buttonStyle(SettingButtonStyle()).handCursor()}
            SettingRow("Fan & Battery Helper",detail:"Hardware controls aren’t available in this build.") {Button("Details") {hardware=true}.buttonStyle(SettingButtonStyle()).handCursor()}
        }
    }
    private var menu:some View {
        Group {
            SettingRow("Show Menu Bar Icon",detail:"Show Bonsai in the menu bar.") {Toggle("Show menu bar icon",isOn:$menuVisible).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor()}
            SettingRow("Swap Click Actions",detail:"Swap left-click Status and right-click menu.") {Toggle("Swap Click Actions",isOn:$swapClicks).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor().disabled(!menuVisible)}
            SettingRow("Cmd+Q Behavior",detail:"Quit the app or keep the menu bar running.") {SoftwareTabs(selection:$quitBehavior,accessibilityTitle:"Cmd+Q behavior",compact:true,tint:SettingsColors.sakura,roomy:true,selectionFill:SettingsColors.sakura.opacity(0.24),tabs:[("Quit Bonsai",""),("Keep Menu Bar","")]).disabled(!menuVisible)}
            SettingRow("Open Bonsai Shortcut",detail:"Open Bonsai from any app.") {ShortcutSetting(key:"openShortcut")}
            SettingRow("Menu Bar Display",detail:"Choose the menu bar content.") {
                SoftwareTabs(selection:$menuDisplay,accessibilityTitle:"Menu bar display",compact:true,tint:SettingsColors.sakura,roomy:true,selectionFill:SettingsColors.sakura.opacity(0.24),tabs:[("Tree",""),("CPU",""),("Both","")]).disabled(!menuVisible)
            }
            SettingRow("Temperature Unit",detail:"Use Celsius or Fahrenheit.") {SoftwareTabs(selection:$temperatureUnit,accessibilityTitle:"Temperature unit",compact:true,tint:SettingsColors.sakura,roomy:true,selectionFill:SettingsColors.sakura.opacity(0.24),tabs:[("°C",""),("°F","")])}
        }
    }
    private var notifications:some View {
        Group {
            SettingRow("Allow Notifications",detail:"Turn all Bonsai notifications on or off.") {
                NotificationPreference(key:"notificationsEnabled",title:"Allow all notifications",alerts:model.alerts,defaultValue:true)
            }
            Group {
            SettingRow("Resource Pressure",detail:"Sustained CPU/GPU load or critical RAM and heat.") {NotificationPreference(key:"resourceAlerts",title:"Resource pressure alerts",alerts:model.alerts,defaultValue:true)}
            SettingRow("Device Low Battery",detail:"20% or below on supported connected devices.") {NotificationPreference(key:"bluetoothAlerts",title:"Device low battery",alerts:model.alerts,defaultValue:true)}
            SettingRow("Daily App Updates",detail:"Once per active day, after an automatic check.") {NotificationPreference(key:"dailyUpdateAlerts",title:"Daily app update summary",alerts:model.alerts,defaultValue:true)}
            SettingRow("App Leftover Alerts",detail:"When an app moves to Trash. Review in Apps.") {NotificationPreference(key:"leftoverAlerts",title:"App leftover notifications",alerts:model.alerts,defaultValue:true)}
            SettingRow("Low Disk Space",detail:"When available storage stays low.") {NotificationPreference(key:"lowDiskAlerts",title:"Low disk space alerts",alerts:model.alerts,defaultValue:true)}
            }.disabled(!notificationsEnabled).opacity(notificationsEnabled ? 1:0.5)
            NotificationStatus(alerts:model.alerts).padding(.vertical,12)
        }
    }
    private var protection:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Button {protectedItems=false} label:{Label("Back to Tools",systemImage:"chevron.left")}.buttonStyle(QuietTextStyle()).handCursor();Spacer();Button("Add folder…") {model.chooseFolder("Choose a protected folder") {if let url=$0 {model.addExclusion(url)}}}.buttonStyle(SettingButtonStyle()).handCursor()}
            Text("Protected paths stay visible but guarded in Clean. Removing a protection allows future review; it doesn’t remove any files.").secondaryText()
            SettingsScrollView {VStack(spacing:10) {if model.exclusions.isEmpty {Text("No custom protected paths.").secondaryText().padding(.vertical,30)};ForEach(model.exclusions,id:\.self) {path in HStack {Text(path.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).font(.system(size:11,design:.monospaced)).lineLimit(2).textSelection(.enabled);Spacer();Button("Remove") {model.removeExclusion(path)}.buttonStyle(QuietTextStyle()).handCursor()}.padding(12).bonsaiListSurface(radius:12).bonsaiListHover()}}}
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    private func refreshInputProtection() {
        let trusted=AXIsProcessTrustedWithOptions(nil)
        if inputProtection != trusted {inputProtection=trusted}
        if trusted {inputChecked=false}
    }
    private func openSettings(_ pane:String) {model.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?"+pane)!)}
    private var hardwareDetails:some View {
        VStack(alignment:.leading,spacing:20) {
            Button("Back to Tools") {hardware=false}.buttonStyle(QuietTextStyle()).handCursor()
            Label("Hardware helper not installed",systemImage:"cpu").font(.title3.weight(.semibold))
            Text("Bonsai reads public thermal state, GPU utilization when the driver exposes it, battery charge, cycles and a conditional capacity estimate. These readings do not require a privileged helper.").secondaryText()
            Text("Fan speed overrides, custom charging limits and lid-closed sleep overrides are not supported in this build. There is no signed Bonsai hardware helper to install. Use macOS Battery settings for supported charging options.").secondaryText()
            Button("Open Battery Settings") {model.open(URL(string:"x-apple.systempreferences:com.apple.Battery-Settings.extension")!)}.buttonStyle(SettingButtonStyle()).handCursor()
            Spacer()
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    private var loginDescription:String {
        switch loginState {case .enabled:return "Bonsai opens when you sign in.";case .notRegistered:return "Open Bonsai manually.";case .requiresApproval:return "Approve Bonsai in Login Items.";case .notFound:return "Not registered. Toggle on to retry.";@unknown default:return "macOS login status unavailable."}
    }
    private func changeLogin(_ enabled:Bool) {
        do {if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()};loginState=SMAppService.mainApp.status;loginError=""}
        catch {loginState=SMAppService.mainApp.status;loginError=error.localizedDescription}
    }
}
private struct SettingRow<Control:View>:View {
    var title:String;var detail:String;@ViewBuilder var control:Control
    init(_ title:String,detail:String,@ViewBuilder control:()->Control) {self.title=title;self.detail=detail;self.control=control()}
    private var accent:Color {SettingsColors.sakura}
    var body:some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:7) {
                HStack(alignment:.center,spacing:12) {
                    Text(title).font(.system(size:15,weight:.semibold,design:.rounded))
                        .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    control.controlSize(.regular).fixedSize().frame(minHeight:34,alignment:.trailing)
                }
                Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12)
            Rectangle().fill(Palette.text.opacity(0.075)).frame(height:1).accessibilityHidden(true)
        }.environment(\.bonsaiControlTint,accent).tint(accent).accessibilityElement(children:.contain).designElement("settings.rows")
    }
}

/// Simple fields with a clear chosen value, matching the compact row buttons.
private struct SettingChoice<Value:Hashable>:View {
    var label:String
    @Binding var selection:Value
    var options:[(Value,String)]
    @ViewState private var expanded=false
    var body:some View {
        Button {expanded.toggle()} label: {
            HStack(spacing:8) {Text(options.first {$0.0==selection}?.1 ?? "Choose");Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))}
        }.buttonStyle(SettingButtonStyle()).handCursor()
            .accessibilityLabel(label).accessibilityValue(options.first {$0.0==selection}?.1 ?? "")
            .popover(isPresented:$expanded,attachmentAnchor:.rect(.bounds),arrowEdge:.bottom) {
                SettingsMenuSurface {
                    ForEach(options,id:\.0) {value,title in
                        SettingsMenuOption(title:title,selected:value==selection) {selection=value;expanded=false}
                    }
                }
            }
    }
}
private struct SettingsMenuSurface<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {
        VStack(alignment:.leading,spacing:3) {content}.padding(7).frame(minWidth:200)
            .background(.ultraThinMaterial)
            .overlay(SettingsColors.sakura.opacity(0.045).allowsHitTesting(false))
            .environment(\.bonsaiControlTint,SettingsColors.sakura).bonsaiAppearance()
    }
}
private struct SettingsMenuOption:View {
    var title:String
    var subtitle:String?=nil
    var selected=false
    var action:()->Void
    @ViewState private var hovering=false
    var body:some View {
        Button(action:action) {
            HStack(spacing:9) {
                Image(systemName:selected ? "checkmark":"circle").font(.system(size:10,weight:.semibold)).opacity(selected ? 1:0).frame(width:12)
                VStack(alignment:.leading,spacing:3) {
                    Text(title).font(.system(size:13,weight:.medium,design:.rounded))
                    if let subtitle {Text(subtitle).font(.system(size:11,design:.rounded)).foregroundStyle(Palette.muted)}
                }
                Spacer(minLength:4)
            }.foregroundStyle(Palette.text).padding(.horizontal,10).padding(.vertical,9)
                .background(SettingsColors.sakura.opacity(hovering ? 0.16:selected ? 0.08:0),in:RoundedRectangle(cornerRadius:10))
                .contentShape(RoundedRectangle(cornerRadius:10))
        }.buttonStyle(.plain).handCursor().onHover {hovering=$0}
            .accessibilityAddTraits(selected ? .isSelected:[])
    }
}
private struct SettingButtonStyle:ButtonStyle {
    @Environment(\.bonsaiControlTint) private var tint
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(tint)
            .padding(.horizontal,14).frame(height:34)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
    }
}

private struct ShortcutSetting:View {
    let key:String
    @ViewState private var revision=0
    @ViewState private var expanded=false
    @ViewState private var recording=false
    @ViewState private var feedback=""
    @ObservedObject private var shortcuts=GlobalShortcuts.shared
    private var shortcut:BonsaiShortcut? {BonsaiShortcut.read(key)}
    private var suggested:BonsaiShortcut {
        switch key {
        case "awakeShortcut":return BonsaiShortcut(keyCode:0,modifiers:256|2048|4096,key:"A")
        case "screenShortcut":return BonsaiShortcut(keyCode:1,modifiers:256|2048|4096,key:"S")
        default:return .openDefault
        }
    }
    var body:some View {
        VStack(alignment:.trailing,spacing:5) {
            Button {if recording {recording=false} else {expanded.toggle()}} label: {
                HStack(spacing:8) {
                    Text(recording ? "Press keys…" : shortcut?.title ?? "Off")
                    Image(systemName:recording ? "xmark":"chevron.down").font(.system(size:9,weight:.semibold))
                }
            }.buttonStyle(SettingButtonStyle()).handCursor()
                .accessibilityLabel(key.replacingOccurrences(of:"Shortcut",with:" shortcut"))
                .accessibilityValue(recording ? "Recording. Escape cancels." : shortcut?.title ?? "Off")
                .background(ShortcutCapture(key:key,active:$recording,feedback:$feedback,onChange:{revision+=1}))
                .popover(isPresented:$expanded,attachmentAnchor:.rect(.bounds),arrowEdge:.bottom) {
                    SettingsMenuSurface {
                        SettingsMenuOption(title:"Off",selected:shortcut==nil) {save(nil)}
                        SettingsMenuOption(title:"Suggested Shortcut",subtitle:suggested.title,selected:shortcut==suggested) {save(suggested)}
                        SettingsMenuOption(title:"Manual…",subtitle:shortcut != nil && shortcut != suggested ? shortcut?.title:"Record your own shortcut",selected:shortcut != nil && shortcut != suggested) {
                            expanded=false;feedback="Escape to cancel";recording=true
                        }
                    }
                }
            if recording || !feedback.isEmpty {Text(feedback).font(.system(size:10,design:.rounded)).foregroundStyle(Palette.muted).frame(maxWidth:180,alignment:.trailing)}
            if let error=shortcuts.errors[key] {Text(error).font(.system(size:10)).foregroundStyle(Palette.accent).frame(maxWidth:180)}
        }.onChange(of:recording) {_,value in if !value {feedback=""}}
        .onDisappear {recording=false}
        .id(key+String(revision))
    }
    private func save(_ value:BonsaiShortcut?) {
        if let value,let data=try? JSONEncoder().encode(value) {UserDefaults.standard.set(data,forKey:key)}
        else {UserDefaults.standard.removeObject(forKey:key)}
        expanded=false;recording=false;feedback="";shortcuts.reload();revision+=1
    }
}
private struct NotificationPreference:View {
    let key:String;let title:String
    @AppStorage private var enabled:Bool
    @ObservedObject var alerts:PreferenceAlerts
    @ViewState private var requesting=false
    init(key:String,title:String,alerts:PreferenceAlerts,defaultValue:Bool=false) {self.key=key;self.title=title;self.alerts=alerts;self._enabled=AppStorage(wrappedValue:defaultValue,key)}
    var body:some View {
        Toggle(title,isOn:Binding(get:{enabled},set:{value in if !value {enabled=false;if key=="notificationsEnabled" {alerts.setNotificationsEnabled(false)}} else {requesting=true;Task {enabled=await alerts.request();if key=="notificationsEnabled" {alerts.setNotificationsEnabled(enabled)};requesting=false}}})).labelsHidden().toggleStyle(BonsaiSwitchStyle()).handCursor().disabled(requesting)
    }
}

private struct NotificationStatus:View {
    @ObservedObject var alerts:PreferenceAlerts
    var body:some View {
        HStack(spacing:10) {
            Text("Notifications: "+alerts.authorization).font(.system(size:12,design:.rounded)).foregroundStyle(Palette.muted)
            Spacer(minLength:0)
            if alerts.permissionDenied {Button("Fix") {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)}.buttonStyle(SettingButtonStyle()).handCursor().help("Open macOS Notifications settings")}
        }.task {await alerts.refreshAuthorization()}
    }
}

