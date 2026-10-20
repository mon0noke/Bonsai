import SwiftUI
import AppKit
import BonsaiCore

struct DiskItemScene:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.colorScheme) private var scheme
    @ViewState private var pruningStart:Date?
    let entry:DiskEntry
    private var folderBytes:UInt64 {entry.directory ? entry.measurement.allocated : model.disk?.total ?? entry.measurement.allocated}
    private var folderName:String {entry.directory ? entry.url.lastPathComponent : entry.url.deletingLastPathComponent().lastPathComponent}
    var body:some View {
        GeometryReader {geometry in
            ZStack {
                Palette.background
                RadialGradient(colors:[Palette.sage.opacity(scheme == .dark ? 0.20 : 0.14),.clear],center:.init(x:0.50,y:0.36),startRadius:20,endRadius:geometry.size.width*0.7)
                RadialGradient(colors:[Color(red:0.83,green:0.62,blue:0.42).opacity(0.12),.clear],center:.bottomTrailing,startRadius:0,endRadius:geometry.size.height)
                ScrollView(.vertical,showsIndicators:false) {
                    VStack(spacing:14) {
                        let portraitSize=min(340,max(160,geometry.size.height*0.40))
                        BonsaiCanopy(growth:BonsaiGrowth.level(bytes:folderBytes),pruningStart:pruningStart)
                            .frame(width:portraitSize,height:portraitSize)
                        VStack(spacing:6) {
                            Text(folderName).font(.system(size:12,weight:.semibold)).lineLimit(1)
                            Text(model.diskTrashOutcome?.status=="Trashed" ? "A little more room to grow." : bytes(folderBytes)+" in this \(entry.directory ? "folder" : "location")")
                                .font(.system(size:11)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth:430).help("The bonsai canopy grows with measured folder size. Pruning is an illustration; file sizes are allocated bytes, not guaranteed space recovered.")
                        DiskItemDialog(entry:entry).bonsaiGlass(radius:24,interactive:false).shadow(color:.black.opacity(scheme == .dark ? 0.14 : 0.06),radius:28,y:12)
                    }.frame(maxWidth:.infinity).padding(.vertical,24).frame(minHeight:geometry.size.height)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()

        }.ignoresSafeArea().foregroundStyle(Palette.text).bonsaiAppearance()
            .onChange(of:model.diskTrashOutcome?.id) {_,_ in
                if model.diskTrashOutcome?.status=="Trashed" {pruningStart=Date()}
            }
    }
}

struct DiskItemDialog:View {
    @EnvironmentObject var model:AppModel
    @ViewState private var confirming=false
    @FocusState private var focused:String?
    let entry:DiskEntry
    private var moving:Bool {model.busy && model.operationKind=="disk-trash"}
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:14) {
                Image(nsImage:NSWorkspace.shared.icon(forFile:entry.url.path)).resizable().frame(width:46,height:46).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:7) {
                    Text(model.diskTrashOutcome?.status=="Trashed" ? "Moved to Trash" : confirming ? "Move to Trash?" : entry.url.lastPathComponent)
                        .font(.system(size:21,weight:.semibold)).lineLimit(2)
                    Text(confirming ? entry.url.lastPathComponent+" · "+entry.label : entry.label).font(.system(size:13)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength:8)
                Button(action:model.closeDiskAction) {Image(systemName:"xmark").font(.system(size:11,weight:.semibold)).frame(width:27,height:27).background(Palette.text.opacity(0.08),in:Circle())}.buttonStyle(.plain).handCursor().focusable().focused($focused,equals:"Dismiss").accessibilityLabel("Close item actions").keyboardShortcut(.cancelAction).disabled(moving)
            }
            if let outcome=model.diskTrashOutcome {
                if outcome.status=="Trashed" {
                    Text("You can restore this item from Trash in Finder.").font(.system(size:13)).foregroundStyle(Palette.muted)
                    HStack(spacing:10) {action("Reveal in Finder",symbol:"folder") {model.reveal(outcome.recovery.map {URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))};action("Done",symbol:nil,perform:model.closeDiskAction)}
                } else {
                    Text(outcome.detail).font(.system(size:13)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:10) {action("Reveal in Finder",symbol:"folder") {model.reveal(entry.url)};action("Close",symbol:nil,perform:model.closeDiskAction)}
                }
            } else if moving {
                HStack(spacing:10) {BonsaiActivityGlyph(size:22);Text("Moving to Trash…").font(.system(size:13));Spacer();Button("Cancel",action:model.cancel).handCursor()}
            } else if confirming {
                Text("This item can be restored from Trash later.").font(.system(size:13)).foregroundStyle(Palette.muted)
                HStack(spacing:10) {action("Cancel",symbol:nil) {confirming=false};action("Move to Trash",symbol:"trash",destructive:true) {model.trashDisk(entry)}}
            } else {
                HStack(spacing:10) {action("Reveal in Finder",symbol:"folder") {model.reveal(entry.url);model.closeDiskAction()};action("Move to Trash",symbol:"trash",destructive:true) {confirming=true}}
            }
        }.padding(26).frame(width:430).foregroundStyle(Palette.text)
            .accessibilityElement(children:.contain).accessibilityLabel("File actions for "+entry.url.lastPathComponent)
            .onAppear {focused="Reveal in Finder"}
            .onChange(of:confirming) {_,value in focused=value ? "Cancel" : "Reveal in Finder"}
            .onChange(of:model.diskTrashOutcome?.id) {_,_ in focused=model.diskTrashOutcome?.status=="Trashed" ? "Done" : "Close"}
    }
    private func action(_ title:String,symbol:String?,destructive:Bool=false,perform:@escaping ()->Void)->some View {
        Button(action:perform) {HStack(spacing:7) {if let symbol {Image(systemName:symbol)};Text(title)}.font(.system(size:13,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,13).foregroundStyle(destructive ? Color(red:1,green:0.43,blue:0.41) : Palette.text).background(Palette.text.opacity(0.09),in:Capsule())}
            .buttonStyle(.plain).handCursor().focusable().focusEffectDisabled().focused($focused,equals:title)
            .overlay(Capsule().stroke(Palette.sage.opacity(focused==title ? 0.65 : 0),lineWidth:1.5))
            .onKeyPress(.return) {perform();return .handled}.onKeyPress(KeyEquivalent(" ")) {perform();return .handled}
    }
}

struct DiskFolderPathDialog:View {
    @ViewState private var path:String
    let cancel:()->Void
    let open:(String)->Void
    init(initialPath:String,cancel:@escaping ()->Void,open:@escaping (String)->Void) {
        _path=ViewState(initialValue:initialPath);self.cancel=cancel;self.open=open
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Go to folder").font(.title2)
            TextField("Folder path",text:$path).textFieldStyle(.roundedBorder).accessibilityLabel("Folder path").onSubmit {open(path)}
            HStack {Button("Cancel",action:cancel).keyboardShortcut(.cancelAction);Spacer();Button("Open") {open(path)}.buttonStyle(BonsaiPrimaryButtonStyle()).bonsaiDefaultAction().disabled(path.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}.handCursor()
        }.padding(26).frame(width:520).bonsaiAppearance()
    }
}
