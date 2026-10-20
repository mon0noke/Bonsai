import SwiftUI

/// The only animated canvas exists for the duration of a page switch.
struct LeafPageTransition:View {
    let flight:LeafSweepFlight
    var treeFrame:CGRect? = nil
    let completion:(UUID)->Void
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/60)) {_ in
            LeafSweepCanvas(progress:flight.progress(at:ProcessInfo.processInfo.systemUptime),flight:flight,treeFrame:treeFrame)
        }
            .allowsHitTesting(false).accessibilityHidden(true)
            .task {
                guard !Task.isCancelled else {return}
                let remaining=max(0,LeafSweepFlight.duration-(ProcessInfo.processInfo.systemUptime-flight.startedAt))
                do {try await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000))} catch {return}
                guard !Task.isCancelled else {return}
                completion(flight.id)
            }
    }
}
struct LeafSweepCanvas:View,Animatable {
    var progress:Double
    let flight:LeafSweepFlight
    var treeFrame:CGRect? = nil
    var animatableData:Double {get {progress} set {progress=newValue}}
    var body:some View {
        Canvas {context,size in
            guard size.width>0,size.height>0 else {return}
            let target=treeFrame.flatMap {LeafSweepDynamics.normalizedTarget(frame:$0,size:size)}
            for leaf in LeafSweepDynamics.particles(progress:progress,direction:flight.direction,seed:flight.seed,scene:flight.scene,target:target,treeScale:(treeFrame?.width ?? 512)/512) {
                var drawing=context
                drawing.opacity=leaf.opacity
                drawing.translateBy(x:leaf.position.x*size.width,y:leaf.position.y*size.height)
                drawing.rotate(by:.radians(leaf.angle))
                drawing.scaleBy(x:leaf.width*leaf.flutter,y:leaf.width)
                drawing.fill(Path(BotanicalLeaf.path(flight.scene)),with:.color(Color(nsColor:BotanicalLeaf.color(flight.scene,shade:leaf.shade))))
                var vein=Path();vein.move(to:CGPoint(x:0,y:0.48));vein.addLine(to:CGPoint(x:0,y:-0.36))
                if flight.scene != .oak { drawing.stroke(vein,with:.color(.white.opacity(0.25)),lineWidth:0.045) }
            }
        }
    }
}
