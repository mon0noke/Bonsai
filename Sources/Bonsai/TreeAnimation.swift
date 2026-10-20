import SwiftUI
import AppKit
import SpriteKit

private struct TreeTransitionBreezeKey:EnvironmentKey { static let defaultValue:LeafSweepFlight?=nil }
extension EnvironmentValues {
    var treeTransitionBreeze:LeafSweepFlight? { get {self[TreeTransitionBreezeKey.self]} set {self[TreeTransitionBreezeKey.self]=newValue} }
}

/// SpriteKit deforms the local texture as a continuous mesh; no frame images or external compiler are needed.
struct LivingTree: NSViewRepresentable {
    let image:NSImage
    let kind:NatureScene
    var playing:Bool
    var breeze:LeafSweepFlight? = nil
    var scanning=false
    func makeNSView(context:Context) -> TreeWindView {
        let view=TreeWindView(frame:.zero)
        view.allowsTransparency=true
        view.wantsLayer=true
        view.layer?.isOpaque=false
        view.layer?.backgroundColor=NSColor.clear.cgColor
        view.layer?.allowsGroupOpacity=false
        view.preferredFramesPerSecond=60
        view.ignoresSiblingOrder=true
        view.setAccessibilityElement(false)
        let scene=LivingTreeScene(image:image,kind:kind);scene.setBreeze(breeze);scene.scanning=scanning
        view.presentScene(scene)
        view.requestedPlaying=playing
        return view
    }
    func updateNSView(_ view:TreeWindView,context:Context) { (view.scene as? LivingTreeScene)?.setBreeze(breeze);(view.scene as? LivingTreeScene)?.scanning=scanning;view.requestedPlaying=playing;view.refreshPlayback() }
    static func dismantleNSView(_ view:TreeWindView,coordinator:()) { view.stop() }
}
final class TreeWindView:SKView {
    var requestedPlaying=false
    private var observing=false
    private var running=false
    override var isOpaque:Bool { false }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !observing {
            observing=true
            for name in [NSApplication.didBecomeActiveNotification,NSApplication.didResignActiveNotification,NSApplication.didHideNotification,NSApplication.didUnhideNotification,NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(self,selector:#selector(playbackChanged),name:name,object:nil)
            }
        }
        refreshPlayback()
    }
    @objc private func playbackChanged(_ notification:Notification) { refreshPlayback() }
    func refreshPlayback() {
        preferredFramesPerSecond=max(60,min(120,window?.screen?.maximumFramesPerSecond ?? 60))
        let next=requestedPlaying && NSApp.isActive && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
        if next != running { (scene as? LivingTreeScene)?.resetFrameClock();running=next }
        isPaused = !next
    }
    func stop() {
        requestedPlaying=false;isPaused=true;running=false
        NotificationCenter.default.removeObserver(self);observing=false
        // SwiftUI may composite the outgoing native surface for one final frame.
        // Retain its transparent scene until the view is released: presenting nil
        // here clears SpriteKit's backing drawable during that last composition.
        (scene as? LivingTreeScene)?.resetFrameClock()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
final class LivingTreeScene:SKScene {
    var frameObserver:((TimeInterval)->Void)?
    private let tree:SKSpriteNode
    private let kind:NatureScene
    var scanning=false {
        didSet {
            guard scanning != oldValue else {return}
            if scanning {scanStartedAt=clock.elapsed}
            configureLeaves(count:scanning ? ScanLeafDynamics.count : TreeLeafDynamics.count(kind))
        }
    }
    private var clock=TreeAnimationClock()
    private var scanStartedAt:Double=0
    private var leaves:[SKShapeNode]=[]
    private var breeze:LeafSweepFlight?
    private var ambientOffset:Double=0
    init(image:NSImage,kind:NatureScene) {
        self.kind=kind
        tree=SKSpriteNode(texture:SKTexture(image:image))
        super.init(size:CGSize(width:512,height:512))
        scaleMode = .aspectFit
        backgroundColor = .clear
        tree.size=size
        tree.position=CGPoint(x:256,y:256)
        tree.zPosition=1
        addChild(tree)
        configureLeaves(count:TreeLeafDynamics.count(kind))
    }
    private func configureLeaves(count:Int) {
        while leaves.count>count {leaves.removeLast().removeFromParent()}
        for i in leaves.count..<count {
            let leaf=SKShapeNode(path:Self.leafPath(kind))
            leaf.fillColor=BotanicalLeaf.color(kind,shade:i%3)
            leaf.strokeColor = .clear;leaf.zPosition=2;leaf.alpha=0
            leaf.setScale(CGFloat(0.65+Double(i%3)*0.12))
            leaves.append(leaf);addChild(leaf)
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func resetFrameClock() { clock.resume() }
    func setBreeze(_ flight:LeafSweepFlight?,at time:Double=ProcessInfo.processInfo.systemUptime) {
        let next=flight?.scene == kind ? flight : nil
        if next==nil,let previous=breeze {ambientOffset=previous.progress(at:time)*LeafSweepFlight.duration-clock.elapsed}
        breeze=next
    }
    func ambientTime(at time:Double)->Double { breeze.map {$0.progress(at:time)*LeafSweepFlight.duration} ?? (clock.elapsed+ambientOffset) }
    func ambientBlend(at time:Double)->Double { breeze.map {TreeLeafDynamics.handoff($0.progress(at:time))} ?? 1 }
    func breezeStrength(at time:Double)->Float {
        guard let breeze else {return 0}
        return Float(breeze.direction)*TreeWindDynamics.breezeEnvelope(progress:breeze.progress(at:time))
    }
    override func update(_ currentTime:TimeInterval) {
        frameObserver?(currentTime)
        let time=clock.advance(at:currentTime)
        let strength:Float=kind == .pine ? 0.65 : kind == .maple ? 1.15 : 0.9
        let gust=breezeStrength(at:ProcessInfo.processInfo.systemUptime)
        let destination=TreeWindDynamics.vertices.map { $0+TreeWindDynamics.displacement($0,time:time,strength:strength,gust:gust) }
        tree.warpGeometry=SKWarpGeometryGrid(columns:TreeWindDynamics.columns,rows:TreeWindDynamics.rows,sourcePositions:TreeWindDynamics.vertices,destinationPositions:destination)
        let now=ProcessInfo.processInfo.systemUptime
        let leafTime=ambientTime(at:now),blend=ambientBlend(at:now)
        for (i,leaf) in leaves.enumerated() {
            let pose=scanning ? ScanLeafDynamics.pose(index:i,time:time-scanStartedAt) : TreeLeafDynamics.pose(index:i,time:leafTime)
            leaf.position=CGPoint(x:pose.position.x*512,y:(1-pose.position.y)*512)
            leaf.alpha=CGFloat(pose.opacity*(scanning ? 1 : blend))
            leaf.zPosition=scanning && pose.position.y<0.37 ? 0 : 2
            leaf.zRotation=CGFloat(-pose.angle)
            leaf.yScale=pose.width/8
            leaf.xScale=pose.width/8*pose.flutter
        }
    }
    private static func leafPath(_ kind:NatureScene)->CGPath {
        // SpriteKit is bottom-up; share the silhouette with the top-down Canvas.
        var transform=CGAffineTransform(scaleX:8,y:-8)
        return BotanicalLeaf.path(kind).copy(using:&transform)!
    }
}
