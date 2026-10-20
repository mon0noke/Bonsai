import SwiftUI
import BonsaiCore
import AppKit

struct RootView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var design=DesignPreferences.shared
    @ViewState private var settings=false
    @ViewState private var doctor=false
    @ViewState private var about=false
    @ViewState private var more=false
    @ViewState private var treeHovered=false
    @ViewState private var keyboardFocusVisible=false
    @ViewState private var attachedSheets=0
    @FocusState private var navigationFocus:AppModel.Page?
    private var utilityOpen:Bool {settings || doctor || about}
    private var blurPage:Bool {utilityOpen || model.inspectedProcess != nil || model.diskAction != nil || attachedSheets>0 || model.showReview || model.showResults || model.accessRequest != nil || model.error != nil || !model.dialogTokens.isEmpty}
    var hasDedicatedActivity:Bool { model.page == .software && model.operationKind == "uninstall" || model.page == .optimize && model.operationKind == "maintenance" || model.page == .clean && model.operationKind == "clean" }
    private var hidesNavigation:Bool {model.page == .clean && model.lastScan != nil && !(model.busy && model.operationKind == "clean") || model.page == .optimize && model.maintenanceScreen == .details || model.page == .software && model.uninstallScreen == .details}
    var body:some View {
        VStack(spacing:0) {
                if hidesNavigation { Color.clear.frame(height:BonsaiActivityMotion.titlebarInset).accessibilityHidden(true) }
                if !hidesNavigation { header.fixedSize(horizontal:false,vertical:true).transition(.opacity) }
                if model.busy && !hasDedicatedActivity {
                    BonsaiActivityStrip(title:model.progress,cancelOnEscape:true,cancel:model.cancelForeground).padding(.horizontal,24).padding(.bottom,12)
                }
                if model.page == .software && !model.trashNotices.isEmpty && UserDefaults.standard.bool(forKey:"watchTrashApps") {
                    HStack(spacing:16) {
                        Label("\(model.trashNotices.count) \(model.trashNotices.count == 1 ? "app" : "apps") in Trash",systemImage:"trash")
                            .font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Palette.muted)
                        Spacer(minLength:12)
                        Button {model.page = .clean;model.scanRemnants()} label: {
                            HStack(spacing:7) {Text("Review leftovers");Image(systemName:"arrow.right").font(.system(size:10,weight:.semibold))}
                        }.buttonStyle(LeftoverReviewButtonStyle()).handCursor().disabled(model.busy)
                    }.padding(10).padding(.leading,6).frame(maxWidth:460)
                        .background(Palette.text.opacity(0.035),in:RoundedRectangle(cornerRadius:20,style:.continuous))
                        .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).strokeBorder(Palette.text.opacity(0.08)).allowsHitTesting(false))
                        .frame(maxWidth:.infinity).padding(.horizontal,24).padding(.bottom,8)
                }
                ZStack {
                    pageContent(for:model.page)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped().layoutPriority(-1)
        }.disabled(model.diskAction != nil).allowsHitTesting(model.inspectedProcess==nil && model.diskAction==nil && !utilityOpen).accessibilityElement(children:model.inspectedProcess==nil && model.diskAction==nil && !utilityOpen ? .contain : .ignore).frame(maxWidth:.infinity,maxHeight:.infinity).background(BonsaiBackground(page:model.page)).foregroundStyle(Palette.text).bonsaiAppearance().ignoresSafeArea(.container,edges:.top)
        .environment(\.bonsaiMotionSuppressed,blurPage)
        .blur(radius:blurPage ? 32:0)
        .overlay(alignment:.top) { if more { dropdownOverlay } }
        .onAppear {
            #if BONSAI_DESIGN_EDITOR
            design.navigate={id in
            let section=DesignTarget.find(id)?.section ?? ""
            if section=="Settings" {settings=true;more=false;return}
            settings=false;about=false;doctor=false;more=false
            let page=section=="Navigation" ? String(id.dropFirst("navigation.".count)):section
            switch page {case "Clean":model.page = .clean;case "Apps":model.page = .software;if id=="apps.updateRows" {model.softwareTab="Updates"} else if id=="apps.startupRows" {model.softwareTab="Startup"} else {model.softwareTab="Uninstall"};case "Optimize":model.page = .optimize;case "Analyze":model.page = .analyze;case "Status":model.page = .status;default:break}
            }
            #endif
        }
        .task(id:model.requestedUtility) {if let utility=model.requestedUtility {if utility=="settings" {settings=true} else if utility=="doctor" {doctor=true};model.requestedUtility=nil}}
        .onReceive(NotificationCenter.default.publisher(for:.bonsaiUtility)) {notification in if let utility=notification.object as? String {if utility=="settings" {settings=true} else if utility=="doctor" {doctor=true}}}
        .safeAreaInset(edge:.bottom,spacing:0) { if model.keepAwake { footer } }.frame(minWidth:980,minHeight:650)
        .overlay {
            if let entry=model.diskAction {
                DiskItemScene(entry:entry).id(entry.id).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            if let group=model.inspectedProcess {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {model.inspectedProcess=nil}.accessibilityHidden(true)
                        StatusProcessInspector(initial:group,onClose:{model.inspectedProcess=nil})
                            .frame(width:min(640,geometry.size.width-40),height:min(740,geometry.size.height-32))
                            .bonsaiGlass(radius:26).blur(radius:attachedSheets>0 ? 32:0).shadow(color:.black.opacity(0.2),radius:24,y:10)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }
        .overlay {
            if utilityOpen {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.20).ignoresSafeArea().accessibilityHidden(true)
                        Group {
                            if settings {PreferencesView(onClose:{settings=false})}
                            else if doctor {DoctorView(onClose:{doctor=false})}
                            else {AboutBonsaiView(onClose:{about=false})}
                        }.frame(width:min(settings ? 540:about ? 580:680,geometry.size.width-48),height:min(settings ? 720:about ? 740:650,geometry.size.height-48))
                            .bonsaiGlass(radius:26,interactive:false,frosted:settings).blur(radius:attachedSheets>0 ? 32:0).shadow(color:.black.opacity(0.22),radius:30,y:12)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }
         .onReceive(NotificationCenter.default.publisher(for:NSWindow.willBeginSheetNotification)) {_ in attachedSheets += 1}
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didEndSheetNotification)) {_ in attachedSheets=max(0,attachedSheets-1)}
        .onKeyPress(.tab) { keyboardFocusVisible=true;return .ignored }
        .onChange(of:model.page) { _,page in
            more=false
            if navigationFocus != nil { navigationFocus=page }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in more=false }
        .sheet(isPresented:$model.showReview) { ReviewView().environmentObject(model).compactInterface() }
        .sheet(isPresented:$model.showResults) { ResultsView().environmentObject(model).compactInterface() }
        .sheet(item:$model.accessRequest) {need in RequiredAccessView(need:need).environmentObject(model).compactInterface()}
        .alert("Action needs attention",isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error=nil }})) { Button("OK") { model.error=nil }.handCursor() } message: { Text(model.error ?? "") }
        #if BONSAI_DESIGN_EDITOR
        .transformPreference(DesignRegionKey.self) {regions in if utilityOpen {regions.removeAll {!$0.id.hasPrefix("settings.")}}}
        #endif
    }
    var dropdownOverlay:some View {
        ZStack(alignment:.top) {
            Color.clear.contentShape(Rectangle()).onTapGesture { dismissMore() }.accessibilityHidden(true)
            BonsaiDropdown(keepAwake:model.keepAwake,perform:menuAction,dismiss:dismissMore)
                .frame(width:navigationWidth,alignment:.leading).offset(x:-4,y:88)
                .transition(reduceMotion ? .identity : .opacity.combined(with:.scale(scale:0.98,anchor:.topLeading)).combined(with:.offset(y:-4)))
        }.frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea(.container,edges:.top).animation(reduceMotion ? nil : .easeOut(duration:0.16),value:more)
    }
    func dismissMore() { withAnimation(reduceMotion ? nil : .easeOut(duration:0.16)) { more=false };navigationFocus=model.page }
    func menuAction(_ item:BonsaiNavigationAction) {
        more=false
        switch item {
        case .settings:settings=true
        case .doctor:doctor=true
        case .screenOn:if model.keepAwake { model.awake(false) } else { model.awakeFor(3600) }
        case .cleanScreen:model.screen.start()
        case .about:about=true
        case .updates:model.softwareTab="Updates";model.page = .software
        }
    }
    @ViewBuilder func pageContent(for page:AppModel.Page) -> some View {
        switch page {
        case .clean:CleanView()
        case .analyze:AnalyzeView()
        case .optimize:OptimizeView()
        case .software:SoftwareView(store:model.software,updateStore:model.updateStore).padding(.horizontal,24).padding(.bottom,18)
        case .status:StatusView().padding(.horizontal,12).padding(.top,8).padding(.bottom,12)
        }
    }
    func moveNavigation(_ step:Int) {
        let pages=AppModel.Page.allCases;let index=pages.firstIndex(of:model.page) ?? (step>0 ? pages.count-1 : 0)
        let next=pages[(index+step+pages.count)%pages.count];keyboardFocusVisible=true;model.page=next;navigationFocus=next
    }
    var footer:some View {
        HStack { Label("Screen stays on",systemImage:"sun.max");Spacer();Button("Release") { model.awake(false) }.handCursor().buttonStyle(QuietTextStyle()) }.font(.system(size:10)).foregroundStyle(Palette.muted).padding(.horizontal,24).padding(.vertical,10).background(Palette.background)
    }
    func navID(_ page:AppModel.Page)->String {"navigation."+(page == .software ? "Apps":page.rawValue)}
    func navHeight(_ page:AppModel.Page)->CGFloat {let value=design.value(navID(page));return 40*value.scale*value.height+2*value.spacing}
    func navWidth(_ page:AppModel.Page) -> CGFloat {let base:Double;switch page { case .clean:base=82;case .software:base=74;case .optimize:base=102;case .analyze:base=96;case .status:base=90 };let value=design.value(navID(page));return (base+10)*value.scale*value.width+2*value.spacing }
    private var navigationPages:[AppModel.Page] { AppModel.Page.allCases }
    private var navigationGap:CGFloat {12+design.value("navigation.spacing").spacing}
    // The rail, selection and anchored menu share one layout calculation.
    private var navigationWidth:CGFloat { 8+32+navigationPages.reduce(0) { $0+navWidth($1) }+navigationGap*CGFloat(navigationPages.count) }
    private var selectionOffset:CGFloat {
        guard let index=navigationPages.firstIndex(of:model.page) else { return 0 }
        return 4+32+navigationGap+navigationPages.prefix(index).reduce(0) { $0+navWidth($1)+navigationGap }
    }
    private var selectionAnimation:Animation? { BonsaiNavigationMotion.animation(reduceMotion:reduceMotion) }
    private var navigationSelection:some View {
        Capsule().fill(.white).overlay(Capsule().stroke(.white.opacity(0.85))).frame(width:navWidth(model.page),height:navHeight(model.page)).offset(x:selectionOffset)
    }
    private func navigationLabel(_ page:AppModel.Page) -> some View {
        Text(page == .software ? "Apps" : page.rawValue)
            .font(.system(size:14*design.value(navID(page)).scale,weight:.bold,design:.monospaced))
            .frame(width:navWidth(page),height:navHeight(page))
    }
    var header:some View {
        GlassControls { ZStack {
            ZStack(alignment:.leading) {
                // A persistent pill can reverse mid-flight without replacing its identity.
                navigationSelection.foregroundStyle(.white)
                    .shadow(color:.black.opacity(0.12),radius:3,y:2)
                    .animation(selectionAnimation,value:model.page)
                    .allowsHitTesting(false).accessibilityHidden(true)
                HStack(spacing:navigationGap) {
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration:0.16)) { more.toggle() };keyboardFocusVisible=false } label: {
                        NavigationTreeEmblem(hovered:treeHovered).frame(width:32,height:32).contentShape(Circle())
                    }.onHover {treeHovered=$0}.onDisappear {treeHovered=false}.handCursor().buttonStyle(.plain).accessibilityLabel("More").accessibilityValue(more ? "Expanded" : "Collapsed")
                    ForEach(navigationPages,id:\.self) { page in
                        Button { keyboardFocusVisible=false;model.page=page } label: {
                            navigationLabel(page).foregroundStyle(Palette.muted).contentShape(Capsule())
                        }.handCursor().buttonStyle(.plain).focusable().focusEffectDisabled().focused($navigationFocus,equals:page)
                            .overlay(Capsule().stroke(keyboardFocusVisible && navigationFocus==page ? Palette.text.opacity(0.45) : .clear,lineWidth:1.5))
                            .accessibilityLabel(page == .software ? "Apps" : page.rawValue).accessibilityValue(model.page==page ? "Selected" : "").accessibilityAddTraits(model.page==page ? .isSelected : []).designSelectable(navID(page))
                    }
                }.padding(4)
                // Black lettering follows the moving white surface, including during a reversal.
                HStack(spacing:navigationGap) {
                    Color.clear.frame(width:32,height:32)
                    ForEach(navigationPages,id:\.self) { page in navigationLabel(page) }
                }.padding(4).foregroundStyle(.black)
                    .mask(alignment:.leading) {
                        navigationSelection
                            .animation(selectionAnimation,value:model.page)
                    }.allowsHitTesting(false).accessibilityHidden(true)
            }.frame(width:navigationWidth,height:max(34,navigationPages.map(navHeight).max() ?? 34)+8).modifier(PageNavigationSurface(page:model.page))
                .onKeyPress(.leftArrow) { moveNavigation(-1);return .handled }.onKeyPress(.rightArrow) { moveNavigation(1);return .handled }
        } }.padding(.top,BonsaiActivityMotion.titlebarInset).padding(.bottom,16)
    }
}
struct CleanView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var query=""
    @ViewState private var category="All items"
    @ViewState private var inspected:String?
    @ViewState private var showScanInfo=false
    @ViewState private var expanded=Set<String>()
    @ViewState private var searching=false
    var categories:[String] { Array(Set(model.cleanItems.map {CleanFlow.category($0.category)})).sorted { a,b in
        let ai=CleanFlow.categoryOrder.firstIndex(of:a) ?? 100;let bi=CleanFlow.categoryOrder.firstIndex(of:b) ?? 100
        return ai==bi ? a<b : ai<bi
    } }
    var items:[ReviewItem] { model.cleanItems.filter { (category=="All items" || CleanFlow.category($0.category)==category) && (query.isEmpty || ($0.title+" "+$0.id).localizedCaseInsensitiveContains(query)) }.sorted { $0.measurement.allocated>$1.measurement.allocated } }
    var total:UInt64 { model.cleanItems.reduce(0) { $0+$1.measurement.allocated } }
    var selectedSize:UInt64 { model.cleanItems.filter { model.selected.contains($0.id) }.reduce(0) { $0+$1.measurement.allocated } }
    var focused:ReviewItem? { model.cleanItems.first { $0.id==inspected } }
    var scanLabel:String { model.cleanMode == .caches ? "Scan your Mac" : "Scan "+model.cleanMode.rawValue }
    private var scanning:Bool {model.busy && model.operationKind == "clean"}
    var body:some View {
        VStack(spacing:0) {
            if model.lastScan != nil && !scanning { scannedHeader }
            if model.lastScan != nil && !scanning && searching { BonsaiSearchField(prompt:"Search name or path",text:$query,focusesOnAppear:true).padding(.horizontal,24).padding(.bottom,14) }
            if model.lastScan==nil || scanning { landing }
            else {
                if !model.cleanAccessPaths.isEmpty {
                    HStack {Image(systemName:"lock.shield");Text("\(model.cleanAccessPaths.count) locations skipped or partly measured.");Spacer();Button("Resolve access",action:model.showCleanAccess).handCursor().buttonStyle(SoftCapsuleStyle())}.font(.system(size:12)).foregroundStyle(Palette.muted).padding(.horizontal,24).padding(.bottom,12)
                }
                if model.cleanItems.isEmpty { EmptyState(symbol:model.cleanComplete == true ? "checkmark.circle":"folder.badge.questionmark",title:model.cleanComplete == true ? "Nothing to clean":"No verified candidates",detail:"Open scan details for skipped or unavailable locations. Other cleanup can continue without administrator access.").frame(maxHeight:.infinity) }
                else { resultList }
                resultActions
            }
        }.onChange(of:model.cleanMode) { _,_ in category="All items";inspected=nil;expanded=[];query="" }
        .sheet(isPresented:$showScanInfo) { VStack(alignment:.leading,spacing:16) { HStack { Text("Scan details").font(.title2);Spacer();Button("Done") { showScanInfo=false }.handCursor().keyboardShortcut(.cancelAction) };BonsaiScrollView(edgeInset:24) { Text(model.scanNote).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) };Text("Allocated bytes are deduplicated within each path. Cross-path hardlinks and APFS clones can overstate reclaimable storage. Partial results are lower bounds. Exclusions, credentials, personal container data and cloud documents remain protected. Only specific generated container cache children can be cleaned. System-owned storage is inventory only. Trash uses a separate permanent-deletion review.").secondaryText();Button("Privacy Settings") { model.settings() }.handCursor() }.padding(24).frame(width:660,height:380).bonsaiAppearance().compactInterface() }
    }
    var scannedHeader:some View {
        HStack(alignment:.center,spacing:24) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:12) { Text("Ready to clean").font(.system(size:23,weight:.bold));if let complete=model.cleanComplete { Pill(text:complete ? "Scanned" : "Partial",color:complete ? Palette.accent : .orange) } }
                Text("\(bytes(selectedSize)) selected · \(bytes(total)) found · \(model.cleanItems.count) items · \(categories.count) categories").font(.system(size:12,weight:.medium)).foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing:10) {
                Button(action:model.scanCurrentClean) { Image(systemName:"arrow.clockwise") }
                    .handCursor().buttonStyle(CleanToolbarStyle()).accessibilityLabel("Scan again").help("Scan again").disabled(model.busy)
                Button { model.lastScan=nil;model.cleanItems=[];model.selected=[];inspected=nil;expanded=[];searching=false;query="" } label: { Image(systemName:"xmark") }
                    .handCursor().buttonStyle(CleanToolbarStyle()).accessibilityLabel("Close cleanup results").help("Back to Clean").keyboardShortcut(.cancelAction).disabled(model.busy)
            }.fixedSize()
        }.padding(.horizontal,24).padding(.top,18).padding(.bottom,20)
    }
    var resultList:some View {
        BonsaiScrollView {
            LazyVStack(spacing:8) {
                ForEach(categories,id:\.self) { name in
                    let members=items.filter { CleanFlow.category($0.category)==name }
                    if !members.isEmpty { categoryCard(name,members) }
                }
                if items.isEmpty { EmptyState(symbol:"magnifyingglass",title:"No matches",detail:"Try another name or path.") }
            }.padding(.horizontal,24).padding(.bottom,12)
        }.frame(maxHeight:.infinity)
    }
    func categoryDescription(_ name:String) -> String {
        switch name {
        case "App Caches":return "App temporary files. Regenerated when needed."
        case "Browsers":return "Browser caches. Cookies and sessions stay."
        case "System Caches":return "macOS-managed caches and diagnostics. System-owned locations are inventory only."
        case "Misc":return "Steam and other one-off caches. Regenerated when needed."
        case "Trash":return "Review separately to delete permanently. Never selected automatically."
        case "Logs":return "Diagnostic logs. Review before moving to Trash."
        case "Developer Tools":return "Build and package caches. The next build may take longer."
        case "AI Tools":return "Temporary AI caches. Conversations stay; downloaded models need individual review."
        case "Communication":return "Communication app caches. Running apps remain protected."
        case "Games & media":return "Media and game caches. Inspect what each app will recreate."
        case "Productivity":return "Generated productivity and design app files."
        case "Temporary Files":return "Older temporary files and macOS user caches. Review before removal."
        case "Uninstalled App Leftovers":return "Possible data from removed apps. Kept unselected for your review."
        case "Installers":return "Older installers in Downloads. Keep anything needed for reinstalling."
        case "Cloud Storage":return "Cloud-client caches. Synced personal documents stay protected."
        default:return "Review individual paths, confidence and risk before removal."
        }
    }
    func categoryCard(_ name:String,_ members:[ReviewItem]) -> some View {
        let eligible=members.filter { !model.isGuarded($0) && $0.category != "Trash" && $0.readOnlyReason==nil && $0.measurement.manifest[$0.id]?.owner==getuid() && $0.measurement.complete && !ApplicationActivity.isRunning($0.runningIDs,among:AppModel.runningBundleIDs()) }
        let chosen=members.filter { model.selected.contains($0.id) }
        let isExpanded = expanded.contains(name) || !query.isEmpty
        return VStack(spacing:0) {
            HStack(spacing:14) {
                CategoryCheckbox(selectedCount:chosen.count,itemCount:members.count,label:"Select eligible items in "+name,enabled:!model.busy && (!eligible.isEmpty || !chosen.isEmpty)) {
                    if chosen.isEmpty {model.selected.formUnion(eligible.map(\.id))}
                    else {model.selected.subtract(members.map(\.id))}
                }.frame(width:18,height:18).handCursor().disabled(model.busy || (eligible.isEmpty && chosen.isEmpty))
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.20)) { if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) } } } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:6) { HStack(spacing:8) { Text(name).font(.system(size:13,weight:.semibold));Text("\(chosen.count)/\(members.count) selected").font(.system(size:12,design:.monospaced)).foregroundStyle(Palette.muted) };Text(categoryDescription(name)).font(.system(size:11)).foregroundStyle(Palette.muted) }
                        Spacer(minLength:16)
                        Text(bytes(chosen.reduce(0) { $0+$1.measurement.allocated })+" / "+bytes(members.reduce(0) { $0+$1.measurement.allocated })).font(.system(size:12,weight:.semibold,design:.monospaced)).foregroundStyle(Color(red:0.49,green:0.69,blue:0.84))
                        Image(systemName:"chevron.down").font(.system(size:11,weight:.semibold)).foregroundStyle(Palette.muted).rotationEffect(.degrees(isExpanded ? 180 : 0)).padding(.leading,7)
                    }.contentShape(Rectangle())
                }.handCursor().buttonStyle(.plain).accessibilityLabel(name+", \(members.count) paths").accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }.padding(.horizontal,16).padding(.vertical,14)
            if isExpanded {
                if name=="Trash" { HStack { Text("Items in Trash are kept until you explicitly confirm permanent deletion.").secondaryText();Spacer();Button("Review Trash…") {model.prepareReview(members,title:"Permanently delete from Trash?",selection:[])}.handCursor().buttonStyle(SoftCapsuleStyle()).disabled(model.busy) }.padding(16) }
                VStack(spacing:0) { ForEach(members) { item in itemRow(item);if inspected==item.id { detail(item).padding(18).frame(maxWidth:.infinity,alignment:.leading) } } }.padding(.bottom,6) }
        }.bonsaiListSurface(radius:13).designElement("clean.rows")
    }
    var resultActions:some View {
        HStack(spacing:12) {
            Text("\(model.selected.count) selected").font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted)
            Button("All") {model.selected=Set(items.filter {!model.isGuarded($0) && $0.category != "Trash" && $0.readOnlyReason==nil && $0.measurement.manifest[$0.id]?.owner==getuid() && $0.measurement.complete && !ApplicationActivity.isRunning($0.runningIDs,among:AppModel.runningBundleIDs())}.map(\.id))}.handCursor().buttonStyle(QuietTextStyle()).disabled(model.busy || items.isEmpty)
            Button("None") {model.selected=[]}.handCursor().buttonStyle(QuietTextStyle()).disabled(model.busy || model.selected.isEmpty)
            Button("Recommended",action:model.restoreRecommendedClean).handCursor().buttonStyle(QuietTextStyle()).disabled(model.busy || model.selected==model.recommendedClean)
            Button { searching.toggle();if !searching { query="" } } label: { Label(searching ? "Close search" : "Search",systemImage:searching ? "xmark" : "magnifyingglass") }
                .handCursor().buttonStyle(QuietTextStyle()).accessibilityLabel(searching ? "Close cleanup search" : "Search cleanup paths").keyboardShortcut("f",modifiers:.command)
            Menu {
                Button("Scan details") {showScanInfo=true}
                Divider()
                cleanScanOptions
            } label: { CleanMenuLabel(title:"More") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().handCursor().accessibilityLabel("More cleanup options").disabled(model.busy)
            Spacer()
            Button(model.selected.isEmpty ? "Nothing selected":"Remove · "+bytes(selectedSize)) {
                model.prepareReview(model.cleanItems.filter {model.selected.contains($0.id)},title:"Remove selected files",direct:true)
            }.handCursor().bonsaiPrimary().controlSize(.large).disabled(model.busy || model.selected.isEmpty)
        }.padding(.horizontal,24).padding(.vertical,18)
    }
    @ViewBuilder var cleanScanOptions:some View {
        Button("Scan your Mac",action:model.scanClean)
        Button("App leftovers only",action:model.scanRemnants)
        Button("Choose installer folder…",action:model.scanInstallers)
        Button("Review a project…",action:model.chooseDependencies)
    }
    var landing:some View {
        NatureLanding(scene:.oak,actionTitle:scanLabel,detail:model.cleanMode == .caches ? nil : landingDetail,busy:model.busy && model.operationKind == "clean",progress:model.progress,allocated:model.cleanScanAllocated,action:model.scanCurrentClean,cancel:model.cancel) {EmptyView()}
    }
    var landingDetail:String { switch model.cleanMode { case .caches:return "Find the files your Mac can live without.\nYou decide what goes, and what stays.";case .remnants:return "Find possible leftovers from removed apps.\nInspect each path before letting it go.";case .installers:return "Choose a folder to review older installers.\nKeep anything you might still need.";case .projects:return "Review dependencies and build artifacts\nin a project folder you choose." } }
    func itemRow(_ item:ReviewItem) -> some View { let running = ApplicationActivity.isRunning(item.runningIDs,among:AppModel.runningBundleIDs()); return HStack(spacing:10) {
        Toggle("Select \(item.title)",isOn:Binding(get:{model.selected.contains(item.id)},set:{if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) }})).toggleStyle(.checkbox).labelsHidden().disabled(model.isGuarded(item) || item.category=="Trash" || item.readOnlyReason != nil || item.measurement.manifest[item.id]?.owner != getuid() || running || !item.measurement.complete || model.busy)
        Button { inspected=inspected==item.id ? nil : item.id } label: { HStack { Image(systemName:item.risk=="High" ? "folder.badge.questionmark" : "folder").foregroundStyle(Palette.accent).frame(width:22); VStack(alignment:.leading,spacing:5) { Text(item.title).font(.system(size:12,weight:.medium)).lineLimit(1); Text(item.id.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).font(.system(size:9,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1) }; Spacer(); if model.isGuarded(item) { Pill(text:"GUARDED",color:Palette.muted) };if item.readOnlyReason != nil { Pill(text:"INSPECT",color:Palette.muted) };if running { Pill(text:"RUNNING",color:.orange) }; if !item.measurement.complete { Image(systemName:"exclamationmark.circle").foregroundStyle(.orange) }; Text(item.measurement.label).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted) } }.handCursor().buttonStyle(.plain).help("Inspect \(item.title)").accessibilityLabel("Inspect \(item.title), \(item.measurement.label)")
        Button {model.toggleGuard(item)} label: {
            Image(systemName:model.isGuarded(item) ? "shield.fill" : "shield").font(.system(size:12)).frame(width:26,height:28).contentShape(RoundedRectangle(cornerRadius:7))
        }.handCursor().buttonStyle(.plain).foregroundStyle(Palette.muted).help(model.isGuarded(item) ? "Guarded. Click to remove this exclusion. Size is from its last measurement." : "Guard this path from cleanup").accessibilityLabel((model.isGuarded(item) ? "Unguard " : "Guard ")+item.title).disabled(model.busy)
        Button {model.reveal(item.url)} label: {
            Image(systemName:"folder").font(.system(size:12)).frame(width:26,height:28).contentShape(RoundedRectangle(cornerRadius:7))
        }.handCursor().buttonStyle(.plain).foregroundStyle(Palette.muted).help("Reveal in Finder").accessibilityLabel("Reveal \(item.title) in Finder").disabled(model.busy)
    }.opacity(model.isGuarded(item) ? 0.52 : 1).padding(.horizontal,16).padding(.vertical,12).bonsaiListHover() }
    func detail(_ item:ReviewItem) -> some View { VStack(alignment:.leading,spacing:14) { HStack { Text("Item details").font(.system(size:12,weight:.semibold)); Spacer(); Button { inspected=nil } label: { Image(systemName:"xmark") }.handCursor().buttonStyle(.plain).accessibilityLabel("Close item details") }; Text(item.title).font(.headline).lineLimit(3); Pill(text:item.risk+" risk",color:item.risk=="High" ? .orange : Palette.accent); Text(item.explanation).font(.system(size:11)).foregroundStyle(Palette.muted); if let reason=item.readOnlyReason {Text(reason).font(.system(size:11)).foregroundStyle(.orange)}; Divider(); Text("Confidence").font(.system(size:10,weight:.semibold)); Text(item.confidence).secondaryText(); Text("Allocated "+item.measurement.label+"\nLogical "+bytes(item.measurement.logical)).font(.system(size:10,design:.monospaced)); Text(item.id).font(.system(size:9,design:.monospaced)).textSelection(.enabled).foregroundStyle(Palette.muted); if !item.measurement.complete { Text(item.measurement.issues.joined(separator:"\n")).font(.system(size:10)).foregroundStyle(.orange) }; HStack { Button("Reveal") { model.reveal(item.url) }.handCursor(); Button("Open") { model.open(item.url) }.handCursor() }; Button(model.isGuarded(item) ? "Unguard path" : "Guard path") { model.toggleGuard(item) }.handCursor() }.frame(maxWidth:.infinity,alignment:.leading) }
}
struct CleanRow: View {
    @EnvironmentObject var model: AppModel
    let item: ReviewItem; @Binding var selected: Bool
    var removalLabel:String?=nil
    var running: Bool { ApplicationActivity.isRunning(item.runningIDs,among:AppModel.runningBundleIDs()) }
    var body: some View {
        HStack(alignment:.top,spacing:14) {
            Toggle("Select \(item.title)",isOn:$selected).labelsHidden().toggleStyle(.checkbox).disabled(model.isGuarded(item) || item.readOnlyReason != nil || item.measurement.manifest[item.id]?.owner != getuid() || !item.measurement.complete || running).padding(.top,4)
            VStack(alignment:.leading,spacing:7) { HStack { Text(item.title).font(.system(size:13,weight:.semibold)); Pill(text:item.category,color:Palette.muted); if running { Pill(text:"APP RUNNING",color:.orange) };if let removalLabel {Pill(text:removalLabel,color:removalLabel=="Permanent" ? .orange:Palette.muted)} }; Text(item.explanation).secondaryText(); Text(item.id.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled); HStack { Text("\(item.confidence) · \(item.risk) risk").font(.system(size:10)).foregroundStyle(item.risk=="High" ? .orange : Palette.muted); if !item.measurement.complete { Text(item.measurement.issues.first ?? "Partial scan").font(.system(size:10)).foregroundStyle(.orange) } } }
            Spacer(); VStack(alignment:.trailing,spacing:9) { Text(item.measurement.label).font(.system(size:13,weight:.medium,design:.monospaced)); Menu { Button("Reveal in Finder") { model.reveal(item.url) }.handCursor(); Button("Open") { model.open(item.url) }.handCursor(); Button("Exclude this path") { model.addExclusion(item.url) }.handCursor() } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:28) }
        }.padding(16).bonsaiListSurface(radius:14).bonsaiListHover()
    }
}
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(model.reviewTitle).font(.title2.weight(.semibold)); Spacer(); Button("Cancel") { model.showReview=false }.handCursor().keyboardShortcut(.cancelAction) }
            Text(model.reviewHasPermanentCaches ? "Generated caches marked for permanent removal cannot be restored. Other selected files still move to Trash. Review the paths and choose Delete permanently to confirm." : model.reviewIsPermanent ? "Select the items you want to delete permanently. Bonsai checks their identities and contents again. Everything else stays in Trash." : "Review each path. Bonsai checks ownership, running apps, file identities, and contents again before moving anything. Changed or inaccessible items are skipped.").secondaryText()
            BonsaiScrollView(edgeInset:28) { LazyVStack(spacing:10) { ForEach(model.review) { item in CleanRow(item:item,selected:Binding(get:{model.reviewSelection.contains(item.id)},set:{if $0 { model.reviewSelection.insert(item.id) } else { model.reviewSelection.remove(item.id) }}),removalLabel:model.reviewIsTrashPurge ? "Permanent":UserDefaults.standard.string(forKey:"cacheRemoval")=="Permanent" && CacheRemovalPolicy.permits(item) ? "Permanent":"Trash") } } }
            Card { Text(model.reviewIsPermanent ? "Permanent deletion" : "Recovery").font(.headline); Text(model.reviewIsPermanent ? "This cannot be undone. Deleted items will no longer be available through Put Back. Cancel to keep every selected item where it is." : "Moved items remain in Finder’s Trash. Open Trash, select an item, and choose Put Back where offered, or move it to its recorded original path. Space is freed only after you empty Trash yourself. High-risk data may be needed by your apps or projects.").secondaryText().padding(.top,6) }
            HStack { Button("Validate preview") { model.removeReviewed(dryRun:true) }.handCursor().disabled(model.reviewSelection.isEmpty); Spacer(); Text("\(model.reviewSelection.count) selected").secondaryText(); Button(model.reviewIsPermanent ? "Delete permanently" : "Move to Trash") { model.removeReviewed() }.handCursor().bonsaiPrimary().disabled(model.reviewSelection.isEmpty).bonsaiDefaultAction() }
        }.padding(28).frame(width:800,height:650).background(BonsaiBackground()).bonsaiAppearance()
    }
}
struct ResultsView:View {
    @EnvironmentObject var model:AppModel
    private var counts:String {
        Dictionary(grouping:model.results,by:{$0.status}).sorted {$0.key<$1.key}
            .map {"\($0.value.count) \($0.key.lowercased())"}.joined(separator:" · ")
    }
    private var recoverable:Bool {model.results.contains {$0.recovery != nil}}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(model.resultTitle).font(.system(size:21,weight:.semibold,design:.rounded))
                Spacer()
                Button("Done") {model.showResults=false}.buttonStyle(SoftCapsuleStyle()).handCursor().keyboardShortcut(.cancelAction).bonsaiDefaultAction()
            }
            Text(counts.isEmpty ? "No items changed.":counts).font(.system(size:13,design:.rounded)).foregroundStyle(Palette.muted)
            BonsaiScrollView(edgeInset:24) {
                LazyVStack(spacing:0) {ForEach(model.results) {CompactOutcomeRow(item:$0)}}
            }
            if recoverable {
                HStack {
                    Text("Restore moved items from Trash.").font(.system(size:11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Open Trash") {model.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))}.buttonStyle(SoftCapsuleStyle()).handCursor()
                }
            }
        }.padding(24).frame(width:650,height:min(500,230+CGFloat(min(model.results.count,6))*58)).bonsaiGlass(radius:24,frosted:true).bonsaiAppearance()
    }
}
private struct CompactOutcomeRow:View {
    @EnvironmentObject private var model:AppModel
    let item:ItemOutcome
    @ViewState private var expanded=false
    private var succeeded:Bool {["Trashed","Deleted","Updated","Removed","Exited"].contains(item.status)}
    private var abbreviatedPath:String {item.path.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path+"/",with:"~/")}
    var body:some View {
        VStack(spacing:0) {
            DisclosureGroup(isExpanded:$expanded) {
                VStack(alignment:.leading,spacing:8) {
                    Text(item.detail).font(.system(size:12)).textSelection(.enabled)
                    Text(item.path).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    if let recovery=item.recovery {
                        Button("Show in Trash") {model.reveal(URL(fileURLWithPath:recovery))}.buttonStyle(QuietTextStyle()).handCursor()
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,10)
            } label: {
                HStack(alignment:.center,spacing:12) {
                    Image(systemName:succeeded ? "checkmark.circle":"minus.circle").foregroundStyle(succeeded ? Palette.sage:Palette.muted).frame(width:18)
                    VStack(alignment:.leading,spacing:4) {
                        Text(item.title).font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(1).truncationMode(.middle)
                        Text(abbreviatedPath).font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Text(item.status).font(.system(size:11,weight:.medium)).foregroundStyle(Palette.muted)
                }.padding(.vertical,12).help(item.path+"\n"+item.detail)
            }.tint(Palette.muted)
            Rectangle().fill(Palette.text.opacity(0.07)).frame(height:1).accessibilityHidden(true)
        }
    }
}

private struct LeftoverReviewButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.semibold,design:.rounded))
            .foregroundStyle(Palette.sage).padding(.horizontal,14).frame(height:34)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
    }
}
