import Foundation
import simd

/// Small continuous deformations; normalized roots stay fixed and no time is caught up after a pause.
enum TreeWindDynamics {
    static let columns=12
    static let rows=18
    static let vertices:[SIMD2<Float>] = (0...rows).flatMap { row in
        (0...columns).map { column in SIMD2(Float(column)/Float(columns),Float(row)/Float(rows)) }
    }
    /// The page leaves and tree canopy share this softly arriving and receding breeze.
    static func breezeEnvelope(progress:Double)->Float {
        guard progress.isFinite,progress>0,progress<1 else {return 0}
        let wave=sin(progress * .pi);return Float(wave*wave)
    }
    static func breezeTravel(progress:Double)->Double {
        guard progress.isFinite else {return 0}
        let p=min(1,max(0,progress));return p-sin(p*2 * .pi)/(2 * .pi)
    }
    static func displacement(_ point:SIMD2<Float>,time:Double,strength:Float,gust:Float=0) -> SIMD2<Float> {
        let canopy=max(0,min(1,(point.y-0.19)/0.81))
        let bend=canopy*canopy
        let slow=Float(sin(time*0.55))*0.014
        let ripple=Float(sin(time*1.1+Double(point.x)*7+Double(point.y)*4))*0.0035
        return SIMD2((slow*bend+ripple*canopy+gust*0.010*bend)*strength,Float(sin(time*0.8+Double(point.x)*6))*0.0025*bend*strength)
    }
}
struct TreeAnimationClock {
    private(set) var elapsed:Double=0
    private var previous:Double?
    mutating func resume() { previous=nil }
    mutating func advance(at time:Double) -> Double {
        if let previous { elapsed += min(1.0/15,max(0,time-previous)) }
        previous=time
        return elapsed
    }
}
