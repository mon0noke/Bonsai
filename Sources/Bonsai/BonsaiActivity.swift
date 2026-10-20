import SwiftUI
import AppKit
import BonsaiCore

private struct BonsaiMotionSuppressedKey:EnvironmentKey {static let defaultValue=false}
extension EnvironmentValues {
    var bonsaiMotionSuppressed:Bool {get {self[BonsaiMotionSuppressedKey.self]} set {self[BonsaiMotionSuppressedKey.self]=newValue}}
}

/// Every activity surface shares the same restrained botanical motion.
/// Timelines stop offscreen, when inactive/minimized, and with Reduce Motion.
struct BotanicalTimeline<Content:View>:View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.bonsaiMotionSuppressed) private var suppressed
    @Environment(\.scenePhase) private var scene
    @ViewState private var visible=false
    @ViewState private var awake=false
    @ViewState private var minimized=false
    @ViewState private var start=Date()
    let content:(Double)->Content
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/60,paused:reduced || suppressed || !visible || !awake || minimized || scene != .active)) {context in
            content(reduced || suppressed ? 0 : max(0,context.date.timeIntervalSince(start)))
        }.onAppear {start=Date();visible=true;awake=NSApp.isActive}
            .onDisappear {visible=false}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) {_ in awake=true}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) {_ in awake=false}
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.didMiniaturizeNotification)) {_ in minimized=true}
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.didDeminiaturizeNotification)) {_ in minimized=false;awake=NSApp.isActive}
    }
}

struct BonsaiActivityGlyph:View {
    var size:CGFloat=22
    var body:some View {
        BotanicalTimeline {time in
            Canvas {context,canvas in
                let s=min(canvas.width,canvas.height)
                var stem=Path();stem.move(to:CGPoint(x:s*0.5,y:s*0.87));stem.addQuadCurve(to:CGPoint(x:s*0.52,y:s*0.2),control:CGPoint(x:s*0.36,y:s*0.43))
                context.stroke(stem,with:.color(Palette.sage.opacity(0.75)),style:StrokeStyle(lineWidth:max(1,s*0.045),lineCap:.round))
                for i in 0..<3 {
                    let phase=BonsaiActivityMotion.phase(elapsed:time+Double(i)*0.55,period:3)
                    let opacity=0.4+0.6*(sin(phase*2*Double.pi)+1)/2
                    let center=CGPoint(x:s*(i==1 ? 0.67 : 0.36),y:s*(0.3+Double(i)*0.18))
                    var leafContext=context;leafContext.opacity=opacity
                    leafContext.translateBy(x:center.x,y:center.y);leafContext.rotate(by:.degrees(i==1 ? -35 : 35))
                    leafContext.fill(Path(ellipseIn:CGRect(x:-s*0.13,y:-s*0.08,width:s*0.26,height:s*0.16)),with:.color(i==2 ? Palette.accent : Palette.sage))
                }
            }
        }.frame(width:size,height:size).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct BonsaiActivityPortrait:View {
    var scene:NatureScene
    var body:some View {
        ZStack {
            Circle().fill(Palette.sage.opacity(0.07)).blur(radius:22).padding(32)
            NatureIllustration(scene:scene,scanning:true).offset(x:scene == .oak ? -0.038603*size : 0)
        }.background(GeometryReader {g in Color.clear.onAppear {size=g.size.width}.onChange(of:g.size.width) {_,value in size=value}})
        .accessibilityHidden(true)
    }
    @ViewState private var size:CGFloat=250
}

struct BonsaiActivityStrip:View {
    let title:String
    var detail:String?=nil
    var cancelTitle="Cancel"
    var cancelOnEscape=false
    var cancel:(()->Void)?=nil
    var body:some View {
        HStack(spacing:12) {
            BonsaiActivityGlyph(size:26)
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:12,weight:.medium)).lineLimit(1).truncationMode(.middle)
                if let detail {Text(detail).font(.system(size:10)).foregroundStyle(Palette.muted).lineLimit(1)}
            }.frame(maxWidth:.infinity,alignment:.leading)
            if let cancel {Button(cancelTitle,action:cancel).buttonStyle(SoftCapsuleStyle()).handCursor().keyboardShortcut(cancelOnEscape ? KeyboardShortcut.cancelAction : nil)}
        }.padding(.horizontal,14).padding(.vertical,9).background(Palette.sage.opacity(0.065),in:RoundedRectangle(cornerRadius:14))
        .accessibilityElement(children:.contain)
    }
}

