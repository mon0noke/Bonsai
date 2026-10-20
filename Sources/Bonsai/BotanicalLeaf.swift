import AppKit

/// One botanical silhouette and palette for both ambient and page leaves.
enum BotanicalLeaf {
    static func color(_ scene:NatureScene,shade:Int)->NSColor {
        switch scene {
        case .oak:return [NSColor(calibratedRed:1,green:0.74,blue:0.80,alpha:1),NSColor(calibratedRed:0.97,green:0.61,blue:0.71,alpha:1),NSColor(calibratedRed:1,green:0.86,blue:0.88,alpha:1)][shade]
        case .maple:return [NSColor(calibratedRed:0.96,green:0.47,blue:0.29,alpha:1),NSColor(calibratedRed:0.89,green:0.34,blue:0.26,alpha:1),NSColor(calibratedRed:0.98,green:0.65,blue:0.37,alpha:1)][shade]
        case .elm:return [NSColor(calibratedRed:0.45,green:0.65,blue:0.28,alpha:1),NSColor(calibratedRed:0.62,green:0.74,blue:0.40,alpha:1),NSColor(calibratedRed:0.35,green:0.55,blue:0.23,alpha:1)][shade]
        case .olive:return [NSColor(calibratedRed:0.60,green:0.66,blue:0.47,alpha:1),NSColor(calibratedRed:0.76,green:0.79,blue:0.64,alpha:1),NSColor(calibratedRed:0.48,green:0.57,blue:0.37,alpha:1)][shade]
        case .pine:return [NSColor(calibratedRed:0.45,green:0.70,blue:0.49,alpha:1),NSColor(calibratedRed:0.70,green:0.77,blue:0.45,alpha:1),NSColor(calibratedRed:0.36,green:0.61,blue:0.45,alpha:1)][shade]
        }
    }
    static func path(_ scene:NatureScene)->CGPath {
        let p=CGMutablePath()
        switch scene {
        case .oak:
            // One soft, notched cherry petal, not a broad oak leaf.
            p.move(to:CGPoint(x:0,y:0.50))
            p.addCurve(to:CGPoint(x:-0.08,y:-0.48),control1:CGPoint(x:-0.52,y:0.10),control2:CGPoint(x:-0.47,y:-0.58))
            p.addQuadCurve(to:CGPoint(x:0,y:-0.35),control:CGPoint(x:-0.03,y:-0.49))
            p.addQuadCurve(to:CGPoint(x:0.08,y:-0.48),control:CGPoint(x:0.03,y:-0.49))
            p.addCurve(to:CGPoint(x:0,y:0.50),control1:CGPoint(x:0.47,y:-0.58),control2:CGPoint(x:0.52,y:0.10));p.closeSubpath()
        case .maple:
            let points:[CGPoint]=[.init(x:0,y:-0.58),.init(x:0.12,y:-0.23),.init(x:0.39,y:-0.39),.init(x:0.28,y:-0.06),.init(x:0.52,y:-0.04),.init(x:0.31,y:0.2),.init(x:0.15,y:0.24),.init(x:0,y:0.50),.init(x:-0.15,y:0.24),.init(x:-0.31,y:0.2),.init(x:-0.52,y:-0.04),.init(x:-0.28,y:-0.06),.init(x:-0.39,y:-0.39),.init(x:-0.12,y:-0.23)]
            p.addLines(between:points);p.closeSubpath()
        case .elm,.olive:
            p.addEllipse(in:CGRect(x:-0.23,y:-0.56,width:0.46,height:1.12))
        case .pine:
            // A three-needle fascicle, rather than a broad leaf on a pine.
            for tip in [CGPoint(x:-0.28,y:-0.57),CGPoint(x:0,y:-0.68),CGPoint(x:0.28,y:-0.57)] {
                p.move(to:CGPoint(x:-0.035,y:0.46));p.addLine(to:tip);p.addLine(to:CGPoint(x:0.035,y:0.46));p.closeSubpath()
            }
        }
        return p
    }
}
