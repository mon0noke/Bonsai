import Foundation
import CoreGraphics

/// One replaceable flight: an old task cannot clear a newer page's leaves.
struct LeafSweepFlight:Identifiable {
    let id:UUID
    let scene:NatureScene
    let direction:Double
    let seed:UInt64
    let startedAt:Double
    static let duration=4.2
    init(id:UUID,scene:NatureScene,direction:Double,seed:UInt64,startedAt:Double=ProcessInfo.processInfo.systemUptime) {
        self.id=id;self.scene=scene;self.direction=direction;self.seed=seed;self.startedAt=startedAt
    }
    func progress(at time:Double)->Double { min(1,max(0,(time-startedAt)/Self.duration)) }
}
struct LeafSweepState {
    private(set) var active:LeafSweepFlight?
    mutating func start(scene:NatureScene,direction:Double,seed:UInt64 = .random(in:.min ... .max)) {
        active=LeafSweepFlight(id:UUID(),scene:scene,direction:direction<0 ? -1 : 1,seed:seed)
    }
    @discardableResult mutating func finish(_ id:UUID)->Bool {
        guard active?.id==id else {return false};active=nil;return true
    }
    mutating func cancel() {active=nil}
}
struct LeafSweepParticle {
    let position:CGPoint
    let angle:Double
    let width:CGFloat
    let flutter:CGFloat
    let opacity:Double
    let shade:Int
}
enum LeafSweepDynamics {
    static let count=24
    static func normalizedTarget(frame:CGRect,size:CGSize)->CGRect? {
        guard size.width.isFinite,size.height.isFinite,size.width>0,size.height>0,
              frame.origin.x.isFinite,frame.origin.y.isFinite,frame.width.isFinite,frame.height.isFinite,frame.width>0,frame.height>0 else {return nil}
        return CGRect(x:frame.minX/size.width,y:frame.minY/size.height,width:frame.width/size.width,height:frame.height/size.height)
    }
    static func particles(progress:Double,direction:Double,seed:UInt64,scene:NatureScene = .oak,target:CGRect? = nil,treeScale:CGFloat=1)->[LeafSweepParticle] {
        guard progress.isFinite,progress>0,progress<1,direction.isFinite else {return []}
        let sign=direction<0 ? -1.0 : 1.0
        return (0..<count).compactMap {i in
            let a=unit(seed,index:i,lane:0),b=unit(seed,index:i,lane:1),c=unit(seed,index:i,lane:2)
            let delay=a*(target == nil ? 0.18 : 0.04);let phase=(progress-delay)/(1-delay)
            guard phase>0,phase<1 else {return nil}
            // A sparse field drifts with the same gust that bends the tree canopy.
            let column=Double(i%6),row=Double(i/6)
            if let target,treeScale.isFinite,treeScale>0 {
                let start=CGPoint(x:(column+0.5)/6+(a-0.5)*0.055,y:(row+0.5)/4+(b-0.5)*0.065)
                let pose=TreeLeafDynamics.pose(index:i,time:progress*LeafSweepFlight.duration)
                let carried=i<TreeLeafDynamics.count(scene)
                let crown=carried ? pose.position : CGPoint(x:0.50+cos(Double(i)*2.4)*0.24,y:0.36+sin(Double(i)*2.4)*0.19)
                let end=CGPoint(x:target.minX+crown.x*target.width,y:target.minY+crown.y*target.height)
                let gather=TreeLeafDynamics.smooth((progress-0.18)/0.70)
                let control1=CGPoint(x:start.x+sign*0.16,y:start.y+(row<2 ? -0.10 : 0.10))
                let control2=CGPoint(x:end.x+sign*(0.12+a*0.04),y:end.y-0.12)
                let u=1-gather
                let orbit=sin(gather * .pi)*0.055
                let curl=gather * .pi*2+Double(i)*0.71
                let point=CGPoint(x:sign*orbit*sin(curl)+u*u*u*start.x+3*u*u*gather*control1.x+3*u*gather*gather*control2.x+gather*gather*gather*end.x,
                                  y:orbit*cos(curl)*0.7+u*u*u*start.y+3*u*u*gather*control1.y+3*u*gather*gather*control2.y+gather*gather*gather*end.y)
                let base=b*6+sign*phase*0.65
                let angle=base+atan2(sin(pose.angle-base),cos(pose.angle-base))*gather
                let fadeIn=TreeLeafDynamics.smooth(phase/0.12)
                let alpha=carried ? (0.24*(1-gather)+pose.opacity*gather)*(1-TreeLeafDynamics.handoff(progress))*fadeIn : 0.24*fadeIn*(1-TreeLeafDynamics.smooth((progress-0.70)/0.28))
                return LeafSweepParticle(position:point,angle:angle,width:CGFloat(7+c*6)*(1-gather)+pose.width*treeScale*gather,
                                         flutter:CGFloat(0.85)*(1-gather)+pose.flutter*gather,opacity:alpha,shade:i%3)
            }
            let drift=TreeWindDynamics.breezeTravel(progress:progress)
            let x=(column+0.5)/6+(a-0.5)*0.055+sign*((drift-0.5)*0.14+sin(phase * .pi+b*6)*0.006)
            let y=(row+0.5)/4+(b-0.5)*0.065+(phase-0.5)*0.07+sin(phase * .pi+a*6)*0.008
            return LeafSweepParticle(position:CGPoint(x:x,y:y),angle:b*6+sign*phase*0.65,width:CGFloat(7+c*6),flutter:CGFloat(0.72+abs(cos(phase*2+b*6))*0.28),opacity:Double(TreeWindDynamics.breezeEnvelope(progress:phase))*0.24,shade:i%3)
        }
    }
    private static func unit(_ seed:UInt64,index:Int,lane:Int)->Double {
        var n=seed &+ UInt64(index*3+lane+1) &* 0x9e3779b97f4a7c15
        n=(n ^ (n>>30)) &* 0xbf58476d1ce4e5b9
        n=(n ^ (n>>27)) &* 0x94d049bb133111eb
        return Double((n ^ (n>>31))>>11)/9_007_199_254_740_992
    }
}

/// Shared landing poses allow the window leaves to become the ambient SpriteKit leaves.
enum TreeLeafDynamics {
    static func count(_ scene:NatureScene)->Int { scene == .pine ? 6 : scene == .oak ? 12 : 8 }
    static func smooth(_ value:Double)->Double { let p=min(1,max(0,value));return p*p*(3-2*p) }
    static func handoff(_ progress:Double)->Double { smooth((progress-0.78)/0.18) }
    static func pose(index:Int,time:Double)->LeafSweepParticle {
        // Continuous orbital flow: no cycle wrap or alpha blink at the handoff.
        let t=max(0,time),angle=t*0.32+Double(index)*2.399963
        let radius=0.25+Double(index%3)*0.035
        return LeafSweepParticle(position:CGPoint(x:0.50+cos(angle)*radius+sin(t*0.41+Double(index))*0.025,y:0.40+sin(angle)*0.24),
                                 angle:angle*0.60+Double(index)*0.37,width:CGFloat(8*(0.65+Double(index%3)*0.12)),
                                 flutter:CGFloat(0.65+abs(cos(t*0.36+Double(index)))*0.35),opacity:0.24+sin(angle)*0.065,shade:index%3)
    }
}

/// Scan-only motion: a bounded ring of petals revolves around the canopy.
/// Positions, tumble and flutter share the same period, so the loop has no seam.
enum ScanLeafDynamics {
    static let count=36
    static let period=3.0
    static func pose(index:Int,time:Double)->LeafSweepParticle {
        let t=time.isFinite ? max(0,time) : 0
        let phase=t.truncatingRemainder(dividingBy:period)/period
        let i=max(0,index)%count,angle=phase*2 * .pi+Double(i)*2.399963
        let radius=0.32+Double(i%4)*0.018
        let depth=sin(angle)
        return LeafSweepParticle(position:CGPoint(x:0.50+cos(angle)*radius,y:0.37+depth*(0.18+Double(i%3)*0.025)),
                                 angle:angle+sin(angle*2+Double(i))*0.35,
                                 width:CGFloat((10+Double(i%3)*2)*(0.8+(depth+1)*0.15)),
                                 flutter:CGFloat(0.55+abs(cos(angle*2+Double(i)))*0.45),
                                 opacity:(0.40+(depth+1)*0.16)*TreeLeafDynamics.smooth(t/0.35),shade:i%3)
    }
}
