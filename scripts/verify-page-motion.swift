import Foundation
import CoreGraphics
import AppKit
import SwiftUI

typealias ViewState<Value> = SwiftUI.State<Value>

@main struct VerifyPageMotion {
    @MainActor static func main() {
        var checks=0
        func check(_ value:Bool,_ reason:String) {precondition(value,reason);checks+=1}
        let synchronized=LeafSweepFlight(id:UUID(),scene:.oak,direction:1,seed:9,startedAt:100)
        check(synchronized.progress(at:99)==0 && synchronized.progress(at:100)==0 && synchronized.progress(at:200)==1,"Shared monotonic breeze phase is clamped")
        check(abs(synchronized.progress(at:100+LeafSweepFlight.duration/2)-0.5)<0.000001,"Both renderers sample the same midpoint")
        check(TreeWindDynamics.breezeEnvelope(progress:0)==0 && TreeWindDynamics.breezeEnvelope(progress:1)==0 && TreeWindDynamics.breezeEnvelope(progress:0.5)==1,"Gust arrives and settles without a discontinuity")
        for step in 1..<100 {
            let p=Double(step)/100,epsilon=0.00001
            let rate=(TreeWindDynamics.breezeTravel(progress:p+epsilon)-TreeWindDynamics.breezeTravel(progress:p-epsilon))/(2*epsilon)
            check(abs(rate-Double(TreeWindDynamics.breezeEnvelope(progress:p))*2)<0.00001,"Leaf drift speed follows canopy gust strength")
        }
        check(LeafSweepFlight.duration>=4 && LeafSweepFlight.duration<=5,"Bonsai transition keeps its longer bounded duration")
        for i in 0..<12 {for time in stride(from:0.0,to:40.0,by:0.1) {
            let a=TreeLeafDynamics.pose(index:i,time:time),b=TreeLeafDynamics.pose(index:i,time:time+0.001)
            check(hypot(a.position.x-b.position.x,a.position.y-b.position.y)<0.001,"Ambient petal orbit is continuous without wrapping")
        }}
        var state=LeafSweepState()
        check(state.active==nil,"Idle must not retain a flight")
        for i in 0..<120 {
            let old=state.active?.id
            state.start(scene:NatureScene.allCases[i%3],direction:i%2==0 ? 1 : -1,seed:UInt64(i))
            guard let active=state.active else {fatalError("Missing flight")}
            if let old {check(!state.finish(old) && state.active?.id==active.id,"Stale completion must not clear replacement")}
            check(active.scene==NatureScene.allCases[i%3],"Tree identity must follow the latest request")
            check(active.direction==(i%2==0 ? 1 : -1),"Direction must reverse without a queue")
        }
        let cancelled=state.active!.id;state.cancel()
        check(state.active==nil && !state.finish(cancelled),"Cancellation must clear active work and reject its completion")
        state.start(scene:.pine,direction:-20,seed:0)
        check(state.active?.direction == -1,"Direction normalization")
        check(state.finish(state.active!.id) && state.active==nil,"Current completion returns to idle")
        for invalid in [Double.nan,Double.infinity,-Double.infinity,-1,0,1,2] {
            check(LeafSweepDynamics.particles(progress:invalid,direction:1,seed:0).isEmpty,"Invalid/finished phases must not produce particles")
        }
        for seed:UInt64 in [0,1,9,UInt64.max] {
            for direction in [-1.0,1.0] {
                for step in 1..<100 {
                    let frame=LeafSweepDynamics.particles(progress:Double(step)/100,direction:direction,seed:seed)
                    check(frame.count<=24,"Rendering workload stays bounded")
                    for leaf in frame {
                        check(leaf.position.x.isFinite && leaf.position.y.isFinite && leaf.angle.isFinite && leaf.width.isFinite && leaf.flutter.isFinite && leaf.opacity.isFinite,"Finite geometry at all phases and seed boundaries")
                        check(leaf.opacity>=0 && leaf.opacity<=0.240001 && leaf.width>=7 && leaf.width<=13 && leaf.flutter>=0.72 && leaf.flutter<=1,"Opacity and sizing remain restrained")
                        check(leaf.position.x>=(-0.32) && leaf.position.x<=1.3 && leaf.position.y>=(-0.05) && leaf.position.y<=1.05,"Flight stays near the canvas")
                    }
                }
            }
        }
        let forward=LeafSweepDynamics.particles(progress:0.75,direction:1,seed:9)
        let reverse=LeafSweepDynamics.particles(progress:0.75,direction:-1,seed:9)
        check(forward.count==reverse.count && zip(forward,reverse).allSatisfy {$0.position.x>$1.position.x && $0.position.y==$1.position.y},"Reverse travel preserves pattern while reversing horizontal movement")
        for seed:UInt64 in [0,1,9,UInt64.max] {
            for direction in [-1.0,1.0] {
                let frame=LeafSweepDynamics.particles(progress:0.5,direction:direction,seed:seed)
                check(frame.contains {$0.position.y<0.15} && frame.contains {$0.position.y>0.85},"Leaves must reach the navigation and bottom of the window")
                for row in 0..<3 {for column in 0..<3 {
                    check(frame.contains {$0.position.x>=Double(column)/3 && $0.position.x<Double(column+1)/3 && $0.position.y>=Double(row)/3 && $0.position.y<Double(row+1)/3},"Midflight must cover all nine window regions")
                }}
            }
        }
        _=NSApplication.shared
        let size=CGSize(width:1200,height:800),frame=CGRect(x:420,y:170,width:300,height:300)
        let target=LeafSweepDynamics.normalizedTarget(frame:frame,size:size)!
        check(target==CGRect(x:0.35,y:0.2125,width:0.25,height:0.375),"Landing uses the actual tree rectangle in window coordinates")
        check(LeafSweepDynamics.normalizedTarget(frame:frame,size:.zero)==nil && LeafSweepDynamics.normalizedTarget(frame:.zero,size:size)==nil,"Unavailable geometry must not invent a tree")
        for scene in NatureScene.allCases {
            for seed:UInt64 in [0,1,9,UInt64.max] {for direction in [-1.0,1.0] {
                let early=LeafSweepDynamics.particles(progress:0.14,direction:direction,seed:seed,scene:scene,target:target,treeScale:300/512)
                for row in 0..<3 {for column in 0..<3 {
                    check(early.contains {$0.position.x>=Double(column)/3 && $0.position.x<Double(column+1)/3 && $0.position.y>=Double(row)/3 && $0.position.y<Double(row+1)/3},"Swirl begins across all window regions before gathering")
                }}
                for step in 1..<100 {
                    for leaf in LeafSweepDynamics.particles(progress:Double(step)/100,direction:direction,seed:seed,scene:scene,target:target,treeScale:300/512) {
                        check(leaf.position.x.isFinite && leaf.position.y.isFinite && leaf.angle.isFinite && leaf.width>0 && leaf.width<=13 && leaf.opacity>=0 && leaf.opacity<=0.34,"Curved arrivals stay finite, small and softly visible")
                    }
                }
                let end=LeafSweepDynamics.particles(progress:0.94,direction:direction,seed:seed,scene:scene,target:target,treeScale:300/512)
                check(end.allSatisfy {target.contains($0.position)},"Leaves finish within the real tree rectangle")
                for i in 0..<TreeLeafDynamics.count(scene) {
                    let pose=TreeLeafDynamics.pose(index:i,time:0.94*LeafSweepFlight.duration),leaf=end[i]
                    check(abs(leaf.position.x-(target.minX+pose.position.x*target.width))<0.000001 && abs(leaf.position.y-(target.minY+pose.position.y*target.height))<0.000001,"Arrivals match the actual ambient leaf position")
                    check(abs(Double(leaf.width-pose.width*300/512))<0.000001 && abs(sin(leaf.angle)-sin(pose.angle))<0.000001,"Size and rotation match at the renderer handoff")
                    check(abs(leaf.opacity+pose.opacity*TreeLeafDynamics.handoff(0.94)-pose.opacity)<0.000001,"Crossfade preserves leaf opacity rather than blinking")
                }
            }}
        }
        try! FileManager.default.createDirectory(atPath:"work/leaf-rendering",withIntermediateDirectories:true)
        for scene in NatureScene.allCases {
            let flight=LeafSweepFlight(id:UUID(),scene:scene,direction:1,seed:9)
            let renderer=ImageRenderer(content:LeafSweepCanvas(progress:0.5,flight:flight,treeFrame:CGRect(x:230,y:80,width:180,height:180)).frame(width:640,height:380))
            guard let image=renderer.cgImage else {fatalError("Canvas failed to render")}
            let bitmap=NSBitmapImageRep(cgImage:image)
            var visible=0
            for y in stride(from:0,to:bitmap.pixelsHigh,by:2) {for x in stride(from:0,to:bitmap.pixelsWide,by:2) {if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.01 {visible+=1}}}
            check(visible>30,"Actual leaf Canvas must draw visible botanical shapes")
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"work/leaf-rendering/"+scene.rawValue+".png"))
        }
        print("PASS: actual cherry/maple/pine bonsai Canvas rendering")
        print("PASS: full-window swirl to actual canopy, matched ambient position/size/angle/opacity handoff, bounded arrivals, seed extremes, reversal, cancellation and stale completion")
        print("RESULT: \(checks) assertions, 0 failures")
    }
}
