import Foundation

/// Decorative motion only: never represents a percentage of filesystem work.
public enum BonsaiActivityMotion {
    public struct Leaf:Sendable { public let x:Double;public let y:Double;public let angle:Double;public let opacity:Double }
    public static func phase(elapsed:Double,period:Double=5)->Double {
        guard elapsed.isFinite,period.isFinite,period>0 else {return 0}
        return max(0,elapsed).truncatingRemainder(dividingBy:period)/period
    }
    public static func leaf(index:Int,elapsed:Double)->Leaf {
        let angle=(phase(elapsed:elapsed)+Double(max(0,index)%8)/8)*2*Double.pi
        return Leaf(x:0.5+sin(angle)*0.40,y:0.34+cos(angle)*0.20,angle:angle*180/Double.pi+35,opacity:0.35+0.30*(sin(angle)+1)/2)
    }
    public static func portraitSize(height:Double,checklist:Bool)->Double {
        let height=height.isFinite ? max(0,height) : 0
        return min(300,max(100,height-(checklist ? 330 : 240)))
    }
    public static func scanPortraitSize(height:Double,width:Double)->Double {
        let h=height.isFinite ? max(0,height) : 0,w=width.isFinite ? max(0,width) : 0
        return max(0,min(360,h-160,w-48))
    }
    public static func checklistRows(height:Double)->Int {height>=620 ? 4 : height>=480 ? 2 : 1}
    // In unscaled points; larger than the 28-point native traffic-light zone,
    // including at Bonsai's 0.924 interface scale.
    public static let titlebarInset:Double=44
}
