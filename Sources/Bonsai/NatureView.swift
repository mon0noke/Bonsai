import SwiftUI
import AppKit
import BonsaiCore

struct TreeCanopyAnchorKey:PreferenceKey {
    static var defaultValue:[NatureScene:Anchor<CGRect>] {[:]}
    static func reduce(value:inout [NatureScene:Anchor<CGRect>],nextValue:()->[NatureScene:Anchor<CGRect>]) {value.merge(nextValue(),uniquingKeysWith: {_,new in new})}
}

/// Individual botanical portraits give each landing a distinct visual identity.
struct NatureLanding<Secondary:View>:View {
    var scene:NatureScene
    var actionTitle:String
    var detail:String? = nil
    var busy=false
    var progress=""
    var allocated:UInt64?=nil
    var action:()->Void
    var cancel:()->Void = {}
    @ViewBuilder var secondary:()->Secondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GeometryReader { geometry in
            if busy {
                BonsaiScanPresentation(scene:scene,progress:progress,allocated:allocated,cancel:cancel)
            } else {
                let height=geometry.size.height
                let artHeight=BonsaiActivityMotion.portraitSize(height:height,checklist:false)
                VStack(spacing:0) {
                    NatureIllustration(scene:scene).frame(width:artHeight,height:artHeight)
                        .offset(x:scene == .oak ? -artHeight*0.038603 : 0).designElement("clean.tree")
                    Text(scene.name).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.3)
                        .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        .frame(maxWidth:.infinity).padding(.top,12)
                        .accessibilityLabel("\(scene.name), \(scene.botanicalName)").designElement("clean.caption")
                    Spacer().frame(height:max(16,min(40,height*0.06)))
                    Text(detail ?? scene.verse).font(.system(size:16,weight:.semibold,design:.serif)).lineSpacing(6)
                        .foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth:.infinity).designElement("clean.title")
                    Spacer().frame(height:24)
                    Button(action:action) {Text(actionTitle).frame(width:200,height:28)}.handCursor().bonsaiPrimary().designElement("clean.action")
                    secondary().padding(.top,12)
                }.frame(width:min(530,max(0,geometry.size.width-48)))
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.center)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

/// Images are loaded once; redraws only transform the cached portrait.
enum TreeArtwork {
    static let images:[NatureScene:NSImage] = Dictionary(uniqueKeysWithValues:NatureScene.allCases.compactMap { scene in
        guard let url=Bundle.main.url(forResource:scene.resource,withExtension:"png",subdirectory:"Trees"),let image=NSImage(contentsOf:url) else { return nil }
        return (scene,image)
    })
}

struct NatureIllustration:View {
    var scene:NatureScene
    var scanning=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bonsaiMotionSuppressed) private var suppressed
    @Environment(\.scenePhase) private var phase
    @Environment(\.treeTransitionBreeze) private var breeze
    @ViewState private var visible=false
    @ViewState private var awake=true
    @ViewState private var minimized=false
    var body:some View {
        Group {
            if let image=TreeArtwork.images[scene] {
                // Keep the same drawable when desktop transitions deactivate the app.
                // Swapping to an AppKit image changes color rendering mid-transition.
                if reduceMotion || suppressed {
                    Image(nsImage:image).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true)
                } else {
                    LivingTree(image:image,kind:scene,playing:visible && awake && !minimized && phase == .active,breeze:breeze,scanning:scanning)
                        // The native drawable must not inherit a layout animation
                        // when a scan completes or a parent switches its content.
                        .transaction { $0.animation=nil }
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            } else {
                Text("Tree artwork unavailable").font(.system(size:12)).foregroundStyle(Palette.muted)
            }
        }.anchorPreference(key:TreeCanopyAnchorKey.self,value:.bounds) {[scene:$0]}
            .onAppear { visible=true;awake=NSApp.isActive }
            .onDisappear { visible=false }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in awake=true }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in awake=false }
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.didMiniaturizeNotification)) { _ in minimized=true }
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.didDeminiaturizeNotification)) { _ in minimized=false;awake=NSApp.isActive }
    }
}
