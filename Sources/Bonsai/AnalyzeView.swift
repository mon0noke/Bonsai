import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BonsaiCore

struct AnalyzeView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.colorScheme) private var scheme
    @ViewState private var query=""
    @ViewState private var goingToFolder=false
    @ViewState private var groupDepth=0
    @AppStorage("diskMapFullAccessPromptSeen") private var diskMapFullAccessPromptSeen=false
    @ViewState private var showFirstMapAccess=false
    @ViewState private var checkingMapAccess=false
    @ViewState private var largestMode=false
    @ViewState private var largestFiles:[DiskEntry]=[]
    @ViewState private var largestLoading=false
    @ViewState private var largestComplete=true
    @ViewState private var largestLoadedKey:String?
    private var rootEntries:[DiskEntry] {model.disk?.entries ?? model.diskIncremental}
    private var measuredEntries:[DiskEntry] {rootEntries.filter {$0.measurement.allocated>0}.sorted {$0.measurement.allocated == $1.measurement.allocated ? $0.id<$1.id : $0.measurement.allocated>$1.measurement.allocated}}
    private var entries:[DiskEntry] {groupDepth==0 ? rootEntries.sorted {$0.measurement.allocated>$1.measurement.allocated} : Array(measuredEntries.dropFirst(groupDepth*8))}
    private var visible:[DiskEntry] {(largestMode ? largestFiles:entries).filter {query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)}}
    private var scanning:Bool {model.diskScanning}
    private var groups:[DiskMapGroup] {DiskMapGroup.make(entries)}
    private var total:UInt64 {groupDepth==0 ? model.disk?.total ?? entries.reduce(0) {$0 &+ $1.measurement.allocated} : entries.reduce(0) {$0 &+ $1.measurement.allocated}}
    var body:some View {
        Group {
            if model.disk == nil && entries.isEmpty && !scanning {landing}
            else {
                HStack(spacing:18) {
                    sidebar.frame(width:214)
                    VStack(alignment:.leading,spacing:12) {
                        header
                        if scanning {BonsaiActivityStrip(title:model.diskProgress,cancelTitle:"Stop",cancelOnEscape:true,cancel:model.cancelDisk)}
                        if !model.diskNote.isEmpty {notice(model.diskNote)}
                        map.frame(maxWidth:.infinity,maxHeight:.infinity)
                        footer
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }.padding(.horizontal,22).padding(.bottom,20).padding(.top,8)
            }
        }
        .sheet(isPresented:$showFirstMapAccess) {
            VStack(alignment:.leading,spacing:18) {
                Text("Full Disk Access").font(.system(size:20,weight:.semibold,design:.rounded))
                Text("Allow Bonsai to include protected data in your disk map.").font(.system(size:13)).foregroundStyle(Palette.muted)
                HStack {
                    Button("Not now") {showFirstMapAccess=false;model.scanDisk(overview:true,askForAccess:false)}.buttonStyle(QuietTextStyle()).handCursor().keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Grant Access") {showFirstMapAccess=false;model.settings()}.buttonStyle(SoftCapsuleStyle()).handCursor()
                }
            }.padding(26).frame(width:390).background(Palette.background).bonsaiAppearance().compactInterface()
        }
        .sheet(isPresented:$goingToFolder) {
            DiskFolderPathDialog(initialPath:model.diskOverview ? FileManager.default.homeDirectoryForCurrentUser.path : model.diskRoot.path,cancel:{goingToFolder=false},open:goToFolder).compactInterface()
        }
        .onChange(of:model.diskRoot) {_,_ in query="";groupDepth=0}
        .onChange(of:model.diskOverview) {_,_ in query="";groupDepth=0}
        .task(id:largestRequestKey) {await loadLargestFiles()}
        .onChange(of:scanning) {_,value in if value {groupDepth=0;query=""}}
    }
    private var landing:some View {
        GeometryReader {geometry in
            let portrait=min(360,max(180,geometry.size.height*0.53))
            VStack(spacing:20) {
                Spacer(minLength:12)
                NatureIllustration(scene:.pine).frame(width:portrait,height:portrait).designElement("analyze.tree").accessibilityLabel(NatureScene.pine.name)
                Text("See where your space grows").font(.system(size:23,weight:.medium,design:.serif)).foregroundStyle(Palette.muted).designElement("analyze.title")
                HStack(spacing:12) {
                    Button(action:mapDisk) {Label("Map your disk",systemImage:"internaldrive")}.buttonStyle(AnalyzeActionStyle(primary:true)).handCursor().bonsaiDefaultAction().disabled(!model.canNavigateDisk || checkingMapAccess).designElement("analyze.action")
                    Button {model.chooseDisk()} label:{Label("Choose a folder",systemImage:"folder")}.buttonStyle(AnalyzeActionStyle()).handCursor().disabled(!model.canNavigateDisk).designElement("analyze.choose")
                }
                if !model.diskNote.isEmpty {notice(model.diskNote).frame(maxWidth:540)}
                Spacer(minLength:12)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(24)
        }
    }
    private var sidebar:some View {
        VStack(alignment:.leading,spacing:12) {
            NatureIllustration(scene:.pine,scanning:scanning).frame(width:145,height:145).designElement("analyze.sidebarTree").frame(maxWidth:.infinity)
            Text(model.disk == nil && !scanning && entries.isEmpty ? "Your disk, at a glance" : "\(entries.count) items · \(bytes(total))").font(.system(size:12,weight:.medium)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8).designElement("analyze.caption")
            HStack(spacing:10) {
                sidebarTab("Current Folder",largest:false)
                sidebarTab("Largest Files",largest:true)
                Spacer(minLength:0)
            }
            BonsaiSearchField(prompt:"Find an item",text:$query)
            BonsaiScrollView {
                LazyVStack(spacing:3) {
                    if largestMode && largestLoading {Text("Finding large files…").secondaryText().padding(.vertical,8)}
                    if largestMode && !largestLoading && !largestComplete {Text("Largest files found · partial scan").font(.system(size:10)).foregroundStyle(Palette.muted).padding(.vertical,5)}
                    ForEach(visible) {entry in folderRow(entry)}
                    if visible.isEmpty && !largestLoading {Text(largestMode ? "No matching files." : entries.isEmpty ? scanning ? "Measuring your folders…" : "Start a scan to see your files." : "No matching items.").secondaryText().padding(.top,12)}
                }
            }.frame(maxHeight:.infinity).bonsaiListSurface(radius:12)
            Menu {Button {model.scanDisk(overview:true)} label:{Label("Whole Disk",systemImage:"internaldrive")};Button {model.scanDisk(root:FileManager.default.homeDirectoryForCurrentUser)} label:{Label("Home Folder",systemImage:"house")};Button {model.scanDisk(root:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))} label:{Label("Downloads",systemImage:"arrow.down.folder")};Divider();Button {model.chooseDisk()} label:{Label("Choose Folder…",systemImage:"folder.badge.plus")};Button {goingToFolder=true} label:{Label("Go to Folder…",systemImage:"arrow.turn.down.right")}} label: {Label("Locations",systemImage:"externaldrive")}.menuStyle(.borderlessButton).handCursor().disabled(!model.canNavigateDisk)
        }
    }
    private var header:some View {
        HStack(spacing:10) {
            DiskNavigationButton(title:"Back",symbol:"chevron.left") {
                if groupDepth>0 {groupDepth-=1;query="";return}
                let parent=model.diskRoot.deletingLastPathComponent()
                if model.diskRoot==FileManager.default.homeDirectoryForCurrentUser || parent.path=="/" {model.scanDisk(overview:true)} else {model.scanDisk(root:parent)}
            }.accessibilityLabel("Parent folder").help("Go to the parent folder (⌘[)").keyboardShortcut("[",modifiers:.command).disabled((model.diskOverview && groupDepth==0) || !model.canNavigateDisk)
            ScrollViewReader {navigation in
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:6) {
                    DiskNavigationButton(title:"Whole Disk",current:model.diskOverview && groupDepth==0) {if model.diskOverview {groupDepth=0;query=""} else {model.scanDisk(overview:true)}}.id("overview")
                    if !model.diskOverview {
                        if breadcrumbs().count>3 {
                            Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Palette.muted)
                            Menu {ForEach(Array(breadcrumbs().dropLast(3)),id:\.path) {url in Button(url.path==FileManager.default.homeDirectoryForCurrentUser.path ? NSUserName() : url.lastPathComponent) {model.scanDisk(root:url)}}} label: {Text("…").font(.system(size:14,weight:.semibold)).frame(minWidth:34,minHeight:40).contentShape(Capsule())}
                                .menuStyle(.borderlessButton).handCursor().accessibilityLabel("Earlier folders").help("Jump to an earlier folder")
                        }
                        ForEach(Array(breadcrumbs().suffix(3)),id:\.path) {url in
                            Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Palette.muted)
                            DiskNavigationButton(title:url.path==FileManager.default.homeDirectoryForCurrentUser.path ? NSUserName() : url.lastPathComponent,current:url==model.diskRoot && groupDepth==0) {if url==model.diskRoot {groupDepth=0;query=""} else {model.scanDisk(root:url)}}.help(url.path).id(url.path)
                        }
                    }
                    ForEach(0..<groupDepth,id:\.self) {level in
                        Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(Palette.muted)
                        DiskNavigationButton(title:"\(max(0,measuredEntries.count-(level+1)*8)) items",current:level+1==groupDepth) {groupDepth=level+1;query=""}.id("group-\(level+1)")
                    }
                }.fixedSize(horizontal:true,vertical:false).disabled(!model.canNavigateDisk)
            }
            .task(id:"\(model.diskRoot.path)-\(model.diskOverview)-\(groupDepth)") {
                await Task.yield()
                guard !Task.isCancelled else {return}
                navigation.scrollTo(groupDepth>0 ? "group-\(groupDepth)" : model.diskOverview ? "overview" : model.diskRoot.path,anchor:.trailing)
            }
            }
            DiskMapSummary(total:total,capacity:model.snapshot.diskTotal,free:model.snapshot.diskFree)
            Button {model.scanDisk(refresh:true)} label: {Image(systemName:"arrow.clockwise")}.handCursor().buttonStyle(.plain).disabled(!model.canNavigateDisk).accessibilityLabel("Refresh disk scan").help("Measure this location again")
        }.frame(height:48)
    }
    @ViewBuilder private var map:some View {
        if groups.isEmpty {
            VStack(spacing:14) {
                if scanning {BonsaiActivityPortrait(scene:.pine).frame(width:190,height:190)} else {Image(systemName:"square.grid.2x2").font(.system(size:36,weight:.light)).foregroundStyle(Palette.sage)}
                Text(scanning ? "Building your disk map" : model.disk == nil ? "See where your space goes" : "No measured space in this folder").font(.system(size:22,weight:scanning ? .regular:.semibold,design:scanning ? .serif:.rounded))

                if !scanning {HStack {Button(model.disk == nil ? "Map your disk" : "Scan again") {if model.disk == nil {mapDisk()} else {model.scanDisk(refresh:true)}}.buttonStyle(AnalyzeActionStyle(primary:true)).handCursor().disabled(!model.canNavigateDisk);Button {model.chooseDisk()} label:{Label("Choose a folder",systemImage:"folder")}.buttonStyle(AnalyzeActionStyle()).handCursor().disabled(!model.canNavigateDisk)}}
            }.frame(maxWidth:.infinity,maxHeight:.infinity).bonsaiListSurface(radius:15)
        } else {
            GeometryReader {geometry in
                let tiles=Treemap.diskLayout(groups.map {Double($0.weight)},remainder:groups.firstIndex(where: \.isRemainder),in:CGRect(origin:.zero,size:geometry.size))
                ZStack(alignment:.topLeading) {
                    ForEach(tiles.indices,id:\.self) {index in
                        let tile=tiles[index],group=groups[tile.index]
                        DiskMapTile(group:group,color:mapColor(group.entries.first!.url),rect:tile.rect,action:{if !group.isRemainder {activate(group.entries[0])} else {showMore(group)}})
                            .frame(width:max(0,tile.rect.width-4),height:max(0,tile.rect.height-4)).offset(x:tile.rect.minX+2,y:tile.rect.minY+2)
                            .bonsaiContextMenu(actions:group.isRemainder ? [.init("Show Smaller Items","square.stack.3d.up",perform:{showMore(group)})]:diskActions(group.entries[0]))
                            .disabled(!model.canNavigateDisk)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius:15)).help("Tile areas are balanced for readability; labels show measured sizes.")
        }
    }
    private var footer:some View {
        HStack(alignment:.center,spacing:10) {
            if scanning {Text("Measuring…").foregroundStyle(Palette.muted)}
            else if let disk=model.disk,!disk.complete {
                Label("Some locations skipped",systemImage:"info.circle").foregroundStyle(Palette.muted)
            }
            Spacer()
            if let disk=model.disk {Text(disk.date.formatted(date:.abbreviated,time:.shortened)+(disk.wasCancelled ? " · stopped" : " · saved map")).foregroundStyle(Palette.muted)}
        }.font(.system(size:10)).frame(height:24)
    }
    private func folderRow(_ entry:DiskEntry)->some View {
        DiskFolderRow(entry:entry,color:mapColor(entry.url),actions:diskActions(entry),action:{activate(entry)}).bonsaiContextMenu(actions:diskActions(entry)).disabled(!model.canNavigateDisk).designElement("analyze.rows")
    }
    private func goToFolder(_ rawPath:String) {
        let path=(rawPath.trimmingCharacters(in:.whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else {model.diskNote="Enter an absolute folder path, or start with ~.";goingToFolder=false;return}
        goingToFolder=false;model.scanDisk(refresh:true,root:URL(fileURLWithPath:path,isDirectory:true))
    }
    private func diskActions(_ entry:DiskEntry)->[BonsaiMenuAction] {[
        .init("Copy Path","doc.on.doc",perform:{bonsaiCopy(entry.url.path)}),
        .init("Reveal in Finder","folder",perform:{model.reveal(entry.url)}),
        .init("Move to Trash","trash",group:1,destructive:true,enabled:!model.busy,perform:{inspect(entry)})
    ]}
    private func sidebarTab(_ title:String,largest:Bool)->some View {
        Button {largestMode=largest;query=""} label:{Text(title).font(.system(size:11,weight:largestMode==largest ? .bold:.regular,design:.rounded)).foregroundStyle(largestMode==largest ? Palette.text:Palette.muted).padding(.vertical,8).contentShape(Rectangle())}.buttonStyle(.plain).handCursor().accessibilityAddTraits(largestMode==largest ? .isSelected:[])
    }
    private var largestRootKey:String {model.diskRoot.path+"|"+String(model.diskOverview)+"|"+String(model.disk?.date.timeIntervalSince1970 ?? 0)}
    private var largestRequestKey:String {String(largestMode)+"|"+largestRootKey+"|"+String(scanning)}
    private func loadLargestFiles() async {
        guard largestMode else {largestLoading=false;return}
        guard !scanning else {largestFiles=[];largestLoading=true;return}
        let key=largestRootKey
        guard largestLoadedKey != key else {return}
        largestLoading=true;largestFiles=[]
        let roots=model.diskOverview ? DiskExplorer.overviewLocations():[model.diskRoot]
        let worker=Task.detached(priority:.utility) {try LargestDiskFiles.scan(roots:roots)}
        do {
            let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
            try Task.checkCancellation()
            guard key==largestRootKey else {return}
            largestFiles=result.entries;largestComplete=result.complete;largestLoadedKey=key
        } catch {if !Task.isCancelled {largestComplete=false}}
        if !Task.isCancelled {largestLoading=false}
    }
    private func mapDisk() {
        guard !checkingMapAccess else {return}
        guard !diskMapFullAccessPromptSeen else {model.scanDisk(overview:true);return}
        checkingMapAccess=true
        Task {
            let report=await Task.detached(priority:.utility) {FileAccess.check()}.value
            checkingMapAccess=false;diskMapFullAccessPromptSeen=true
            if report.accessConfirmed {model.scanDisk(overview:true)} else {showFirstMapAccess=true}
        }
    }
    private func showMore(_ group:DiskMapGroup) {
        guard group.isRemainder,!group.entries.isEmpty else {return}
        groupDepth+=1;query=""
    }
    private func activate(_ entry:DiskEntry) {
        if entry.directory {model.scanDisk(root:entry.url)} else {model.inspectDisk(entry)}
    }
    private func inspect(_ entry:DiskEntry) {model.inspectDisk(entry)}
    private func mapColor(_ url:URL)->Color {let value=url.lastPathComponent.utf8.reduce(0) {($0*31+Int($1))%1009};let colors:[Color]=scheme == .dark ? [Color(red:0.26,green:0.40,blue:0.32),Color(red:0.37,green:0.37,blue:0.25),Color(red:0.32,green:0.40,blue:0.44),Color(red:0.43,green:0.34,blue:0.31),Color(red:0.37,green:0.34,blue:0.44),Color(red:0.28,green:0.42,blue:0.40)] : [Color(red:0.75,green:0.84,blue:0.71),Color(red:0.89,green:0.82,blue:0.63),Color(red:0.69,green:0.81,blue:0.87),Color(red:0.90,green:0.75,blue:0.67),Color(red:0.80,green:0.75,blue:0.86),Color(red:0.68,green:0.83,blue:0.77)];return colors[value%colors.count]}
    private func breadcrumbs()->[URL] {var result:[URL]=[];var url=model.diskRoot;let home=FileManager.default.homeDirectoryForCurrentUser;while url.path != "/" {result.insert(url,at:0);if url==home {break};url.deleteLastPathComponent()};return result}
    private func notice(_ message:String)->some View {HStack {Image(systemName:"exclamationmark.circle");Text(message).lineLimit(3);Spacer();Button("Retry") {model.scanDisk(refresh:true)}.handCursor()}.font(.system(size:11)).foregroundStyle(Palette.muted).padding(10).background(Palette.card,in:RoundedRectangle(cornerRadius:10))}

}

private struct DiskMapSummary:View {
    let total:UInt64;let capacity:UInt64;let free:UInt64
    private var used:UInt64 {capacity>=free ? capacity-free:0}
    private var fraction:Double {capacity>0 ? min(1,Double(total)/Double(capacity)):0}
    var body:some View {
        HStack(spacing:10) {
            GeometryReader {geometry in
                Capsule().fill(Palette.text.opacity(0.09))
                    .overlay(alignment:.leading) {Capsule().fill(Palette.sage.opacity(0.85)).frame(width:geometry.size.width*fraction)}
            }.frame(width:54,height:3).accessibilityHidden(true)
            (Text(bytes(total)).fontWeight(.semibold).foregroundStyle(Palette.text)+Text(" in view").foregroundStyle(Palette.muted))
            Rectangle().fill(Palette.line).frame(width:1,height:11)
            Text("\(bytes(used)) / \(bytes(capacity)) used").foregroundStyle(Palette.muted)
        }.font(.system(size:10,weight:.medium,design:.rounded)).monospacedDigit().fixedSize()
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(bytes(total)) in view, \(String(format:"%.2f",fraction*100)) percent of disk capacity. \(bytes(used)) used of \(bytes(capacity)).")
            .help("The bar shows items in view as a share of total disk capacity.")
    }
}
private enum DiskMapIcon {
    static func symbol(_ entry:DiskEntry)->String {
        if entry.measurement.manifest[entry.url.path]?.isSymlink == true {return "link"}
        let ext=entry.url.pathExtension.lowercased()
        if ext=="app" {return "app"}
        if entry.directory {
            switch entry.url.lastPathComponent.lowercased() {
            case "downloads":return "arrow.down.folder"
            case "applications":return "app.badge"
            case "pictures","photos":return "photo.on.rectangle"
            case "music":return "music.note"
            case "movies":return "film"
            case "documents":return "doc.text"
            case "library":return "books.vertical"
            case "desktop":return "desktopcomputer"
            default:return entry.url==FileManager.default.homeDirectoryForCurrentUser ? "house":"folder"
            }
        }
        if ["dmg","iso","sparseimage","sparsebundle"].contains(ext) {return "internaldrive"}
        if ["pkg","mpkg"].contains(ext) {return "shippingbox"}
        if ["zip","gz","bz2","xz","tar","7z","rar"].contains(ext) {return "doc.zipper"}
        if ["doc","docx","rtf","pages"].contains(ext) {return "doc.richtext"}
        if ["ppt","pptx","key"].contains(ext) {return "rectangle.on.rectangle"}
        guard let type=UTType(filenameExtension:ext) else {return "doc"}
        if type.conforms(to:.image) {return "photo"}
        if type.conforms(to:.movie) {return "film"}
        if type.conforms(to:.audio) {return "music.note"}
        if type.conforms(to:.pdf) {return "doc.richtext"}
        if type.conforms(to:.spreadsheet) {return "tablecells"}
        if type.conforms(to:.sourceCode) {return "chevron.left.forwardslash.chevron.right"}
        if type.conforms(to:.text) {return "doc.text"}
        return "doc"
    }
}

private struct DiskMapTile:View {
    let group:DiskMapGroup;let color:Color;let rect:CGRect;let action:()->Void
    @ViewState private var hovered=false
    @FocusState private var focused:Bool
    @Environment(\.isEnabled) private var isEnabled
    private var title:String {group.isRemainder ? "More items" : group.title}
    private var detail:String {group.isRemainder ? "\(group.entries.count) items · \(group.label)" : group.label}
    private var symbol:String {group.isRemainder ? "square.stack.3d.up" : DiskMapIcon.symbol(group.entries[0])}
    private var caption:some View {
        VStack(spacing:6) {
            HStack(spacing:7) {
                Image(systemName:symbol).font(.system(size:14,weight:.regular)).opacity(0.75).accessibilityHidden(true)
                Text(title).font(.system(size:rect.width>200 ? 14 : 12,weight:.semibold)).lineLimit(2).truncationMode(.middle)
            }
            Text(detail).font(.system(size:11)).opacity(0.75)
        }.foregroundStyle(Palette.text).padding(12)
    }
    var body:some View {
        Button(action:action) {
            RoundedRectangle(cornerRadius:10).fill(color.opacity(hovered ? 0.83 : 1))
                .overlay {if rect.width>75 && rect.height>52 {caption} else if rect.width>24 && rect.height>24 {Image(systemName:symbol).font(.system(size:13,weight:.regular)).foregroundStyle(Palette.text.opacity(0.65))}}
                .overlay(RoundedRectangle(cornerRadius:10).stroke(Palette.text.opacity(hovered || focused ? 0.35 : 0.04),lineWidth:hovered || focused ? 1.5 : 1))
        }.buttonStyle(.plain).handCursor().focusable().focusEffectDisabled().focused($focused).onKeyPress(.return) {guard isEnabled else {return .ignored};action();return .handled}.onKeyPress(KeyEquivalent(" ")) {guard isEnabled else {return .ignored};action();return .handled}.onHover {hovered=$0}.help(title+" · "+detail).accessibilityLabel(title+", "+detail).accessibilityHint(group.isRemainder ? "Show smaller items" : group.entries[0].directory ? "Open folder in disk map" : "Inspect file")
    }
}

private struct DiskFolderRow:View {
    let entry:DiskEntry;let color:Color;let actions:[BonsaiMenuAction];let action:()->Void
    @ViewState private var hovered=false
    var body:some View {
        HStack(spacing:4) {
            Button(action:action) {
                HStack(spacing:9) {
                    Image(systemName:DiskMapIcon.symbol(entry)).foregroundStyle(color).font(.system(size:14)).frame(width:18)
                    VStack(alignment:.leading,spacing:4) {
                        Text(entry.url.lastPathComponent).font(.system(size:12,weight:.medium)).lineLimit(1)
                        Text(entry.label).font(.system(size:10)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.padding(.vertical,10).contentShape(Rectangle())
            }.buttonStyle(.plain).handCursor().help(entry.url.path).accessibilityLabel(entry.url.lastPathComponent+", "+entry.label)
            BonsaiActionMenu(label:"File actions for "+entry.url.lastPathComponent,actions:actions)
        }.padding(.horizontal,8).background(Palette.text.opacity(hovered ? 0.06:0),in:RoundedRectangle(cornerRadius:9)).onHover {hovered=$0}
    }
}

private struct DiskNavigationButton:View {
    let title:String
    var symbol:String?=nil
    var current=false
    let action:()->Void
    @ViewState private var hovered=false
    @FocusState private var focused:Bool
    @Environment(\.isEnabled) private var isEnabled
    var body:some View {
        Button(action:action) {
            HStack(spacing:7) {
                if let symbol {Image(systemName:symbol).font(.system(size:13,weight:.semibold))}
                Text(title).font(.system(size:13,weight:current || symbol != nil ? .semibold : .medium)).lineLimit(1).truncationMode(.middle).frame(width:title.count>24 ? 160 : nil)
            }.padding(.horizontal,symbol == nil ? 12 : 16).frame(height:40)
                .foregroundStyle(current || symbol != nil ? Palette.text : Palette.muted)
                .background(Palette.text.opacity(hovered || focused ? 0.13 : current || symbol != nil ? 0.07 : 0),in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).handCursor().focusable().focusEffectDisabled().focused($focused)
            .overlay(Capsule().stroke(Palette.sage.opacity(focused ? 0.65 : 0),lineWidth:1.5))
            .onKeyPress(.return) {guard isEnabled else {return .ignored};action();return .handled}
            .onKeyPress(KeyEquivalent(" ")) {guard isEnabled else {return .ignored};action();return .handled}
            .onHover {hovered=$0}
    }
}

private struct AnalyzeActionStyle:ButtonStyle {
    var primary=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:14,weight:.semibold,design:.rounded))
            .frame(minWidth:150).padding(.horizontal,20).frame(height:44)
            .foregroundStyle(primary ? Palette.ink:Palette.text)
            .background {
                if primary {Capsule().fill(Palette.sage)}
                else {Capsule().fill(.ultraThinMaterial)}
            }
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
            .environment(\.bonsaiControlTint,Palette.sage)
    }
}
