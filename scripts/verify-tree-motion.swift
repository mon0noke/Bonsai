import Foundation
import AppKit
import SpriteKit

@main struct VerifyTreeMotion {
    static func main() throws {
        var checks=0
        func check(_ condition:Bool,_ message:String) { precondition(condition,message);checks+=1 }
        check(TreeWindDynamics.vertices.count==247,"Grid size must stay bounded")
        for strength:Float in [0.65,0.9,1.15,1.4] {
            for time in stride(from:0.0,through:60,by:0.5) {
                let mapped=TreeWindDynamics.vertices.map { $0+TreeWindDynamics.displacement($0,time:time,strength:strength) }
                for (p,q) in zip(TreeWindDynamics.vertices,mapped) {
                    check(q.x.isFinite && q.y.isFinite,"Non-finite geometry")
                    check(abs(q.x-p.x)<0.035 && abs(q.y-p.y)<0.004,"Breeze must remain bounded")
                    if p.y<=0.19 { check(p==q,"Roots must remain planted") }
                }
                for row in 0..<TreeWindDynamics.rows {
                    for col in 0..<TreeWindDynamics.columns {
                        let index=row*(TreeWindDynamics.columns+1)+col
                        let p=mapped[index],right=mapped[index+1],up=mapped[index+TreeWindDynamics.columns+1]
                        let area=(right.x-p.x)*(up.y-p.y)-(right.y-p.y)*(up.x-p.x)
                        check(area>0,"Warp must not fold or invert cells")
                    }
                }
            }
        }
        var clock=TreeAnimationClock()
        check(clock.advance(at:100)==0,"First frame starts at zero")
        let elapsed=clock.advance(at:100.03)
        clock.resume()
        check(clock.advance(at:10000)==elapsed,"Resume must not catch up a hidden interval")
        check(clock.advance(at:9999)==elapsed,"Clock must not move backwards")
        check(clock.advance(at:20000)<=elapsed+1.0/15,"Frame gap must stay capped")
        for time in [-1.0,0,0.2,1.0,2.999999,3,600,1e12,Double.nan,Double.infinity] {
            for index in [-1,0,17,35,36,Int.max] {
                let pose=ScanLeafDynamics.pose(index:index,time:time)
                check(pose.position.x.isFinite && pose.position.y.isFinite && pose.angle.isFinite,"Scan orbit handles malformed and long-running clocks")
                check((0.10...0.90).contains(pose.position.x) && (0.13...0.61).contains(pose.position.y),"Scan leaves stay around the canopy and clear of the controls")
                check(pose.width>0 && pose.width<16 && pose.flutter>=0.55 && pose.flutter<=1 && pose.opacity>=0 && pose.opacity<=0.721,"Scan particles remain bounded")
            }
        }
        for index in 0..<ScanLeafDynamics.count {
            let end=ScanLeafDynamics.pose(index:index,time:ScanLeafDynamics.period-0.000001),start=ScanLeafDynamics.pose(index:index,time:ScanLeafDynamics.period)
            check(abs(end.position.x-start.position.x)<0.00001 && abs(end.position.y-start.position.y)<0.00001,"Orbit position loops without a jump")
            check(abs(atan2(sin(end.angle-start.angle),cos(end.angle-start.angle)))<0.00001 && abs(end.width-start.width)<0.00001 && abs(end.flutter-start.flutter)<0.00001 && abs(end.opacity-start.opacity)<0.00001,"Tumble, scale, flutter and opacity share a seamless loop")
        }
        _=NSApplication.shared
        for kind in NatureScene.allCases {
            let path="Resources/Trees/"+kind.resource+".png"
            guard let image=NSImage(contentsOfFile:path) else { fatalError("Missing tree: "+path) }
            let scene=LivingTreeScene(image:image,kind:kind)
            check(scene.children.count==(TreeLeafDynamics.count(kind)+1),"Leaves must be bounded")
            let sprite=scene.children.compactMap { $0 as? SKSpriteNode }.first!
            scene.update(0);let first=sprite.warpGeometry as! SKWarpGeometryGrid
            for step in 1...60 { scene.update(Double(step)/30) }
            let next=sprite.warpGeometry as! SKWarpGeometryGrid
            check(first.vertexCount==247 && next.vertexCount==247,"Renderer mesh topology")
            check(simd_distance(first.destPosition(at:240),next.destPosition(at:240))>0.001,"Actual renderer canopy must animate")
            check(first.destPosition(at:0)==next.destPosition(at:0),"Renderer root must remain fixed")
            scene.scanning=true
            for step in 61...120 {scene.update(Double(step)/30)}
            let scanning=sprite.warpGeometry as! SKWarpGeometryGrid
            check(scanning.destPosition(at:0)==next.destPosition(at:0),"Scan orbit keeps the pot anchored")
            let leaves=scene.children.compactMap { $0 as? SKShapeNode }
            check(leaves.count==ScanLeafDynamics.count,"Actual scan renderer uses the bounded denser leaf pool")
            check(leaves.allSatisfy { $0.alpha>=0 && $0.alpha<=0.721 },"Leaf alpha bounds")
            check(leaves.contains {$0.zPosition<sprite.zPosition} && leaves.contains {$0.zPosition>sprite.zPosition},"Actual scan leaves revolve behind and in front of the bonsai")
            let before=scanning.destPosition(at:240);scene.resetFrameClock();scene.update(10000)
            check((sprite.warpGeometry as! SKWarpGeometryGrid).destPosition(at:240)==before,"Renderer resumes without a jump")
            scene.scanning=false
            check(scene.children.count==TreeLeafDynamics.count(kind)+1,"Leaving scan restores the sparse ambient leaf pool")
            let flight=LeafSweepFlight(id:UUID(),scene:kind,direction:-1,seed:9,startedAt:100)
            scene.setBreeze(flight)
            check(abs(scene.breezeStrength(at:100+LeafSweepFlight.duration/2)+1)<0.000001,"Actual SpriteKit scene receives the shared reversed gust")
            check(scene.breezeStrength(at:100)==0 && scene.breezeStrength(at:200)==0,"Gust starts and finishes quietly")
            check(scene.ambientBlend(at:100)==0 && scene.ambientBlend(at:100+LeafSweepFlight.duration*0.96)==1,"Ambient leaves appear as the window leaves land")
            let landingTime=100+LeafSweepFlight.duration*0.98
            let beforeHandoff=scene.ambientTime(at:landingTime)
            scene.setBreeze(nil,at:landingTime)
            check(abs(scene.ambientTime(at:landingTime)-beforeHandoff)<0.000001,"Ambient clock continues from the arriving leaves without resetting")
            scene.setBreeze(LeafSweepFlight(id:UUID(),scene:kind == .oak ? .maple : .oak,direction:1,seed:9,startedAt:100))
            check(scene.breezeStrength(at:100+LeafSweepFlight.duration/2)==0,"Different tree species cannot receive an unrelated flight")
            scene.setBreeze(nil)
            check(scene.breezeStrength(at:100+LeafSweepFlight.duration/2)==0,"Cancellation removes the shared gust")
            for gust:Float in [-1,1] {
                let mapped=TreeWindDynamics.vertices.map {$0+TreeWindDynamics.displacement($0,time:12,strength:1.15,gust:gust)}
                for (p,q) in zip(TreeWindDynamics.vertices,mapped) {
                    check(q.x.isFinite && q.y.isFinite && abs(q.x-p.x)<0.04,"Transition gust deformation remains finite and restrained")
                    if p.y<=0.19 {check(p==q,"Gust cannot move planted roots")}
                }
                for row in 0..<TreeWindDynamics.rows {for col in 0..<TreeWindDynamics.columns {
                    let index=row*(TreeWindDynamics.columns+1)+col
                    let p=mapped[index],right=mapped[index+1],up=mapped[index+TreeWindDynamics.columns+1]
                    check((right.x-p.x)*(up.y-p.y)-(right.y-p.y)*(up.x-p.x)>0,"Transition gust must not fold the rendered grid")
                }}
            }

        }
        print("PASS: five actual SpriteKit meshes, bounded seamless 36-leaf scan orbit, front/back canopy depth, planted roots, scan/ambient pool lifecycle, continuous clock and species filtering; native playback requires GUI checks")
        print("RESULT: \(checks) assertions, 0 failures")
    }
}
