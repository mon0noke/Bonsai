import AppKit

// Original native emblem: the approved navigation bonsai on an ivory tile.
// This master supplies both navigation artwork and every app-icon resolution.
let destination=CommandLine.arguments[1]
let size=1024
let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
NSGraphicsContext.current?.shouldAntialias=true
let context=NSGraphicsContext.current!.cgContext
context.translateBy(x:0,y:CGFloat(size));context.scaleBy(x:1,y:-1)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor {NSColor(deviceRed:r,green:g,blue:b,alpha:1)}
color(0.98,0.97,0.94).setFill()
// An opaque master lets macOS apply its own icon mask without a gray fallback.
NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
let inset=CGFloat(size)/8, extent=CGFloat(size)*0.75
func point(_ x:CGFloat,_ y:CGFloat)->NSPoint {NSPoint(x:inset+x*extent,y:inset+y*extent)}
let trunk=NSBezierPath()
trunk.move(to:point(0.50,0.76));trunk.curve(to:point(0.43,0.27),controlPoint1:point(0.36,0.64),controlPoint2:point(0.63,0.44))
trunk.move(to:point(0.49,0.48));trunk.line(to:point(0.26,0.37))
trunk.move(to:point(0.49,0.52));trunk.line(to:point(0.72,0.42))
trunk.lineWidth=extent*0.065;trunk.lineCapStyle = .round
color(0.40,0.29,0.23).setStroke();trunk.stroke()
for (index,position) in [(0,(0.43,0.24)),(1,(0.25,0.35)),(2,(0.71,0.39)),(3,(0.49,0.40))] {
    let width=extent*(index==0 ? 0.42:0.33),height=extent*0.21
    let center=point(position.0,position.1)
    (index==0 ? color(0.97,0.72,0.70):color(0.64,0.80,0.63)).setFill()
    NSBezierPath(ovalIn:NSRect(x:center.x-width/2,y:center.y-height/2,width:width,height:height)).fill()
}
let pot=NSBezierPath()
pot.move(to:point(0.27,0.74));pot.line(to:point(0.73,0.74))
// Quadratic curves converted exactly to cubic control points.
pot.curve(to:point(0.63,0.89),controlPoint1:point(0.7233333333,0.8266666667),controlPoint2:point(0.69,0.8766666667))
pot.line(to:point(0.37,0.89))
pot.curve(to:point(0.27,0.74),controlPoint1:point(0.31,0.8766666667),controlPoint2:point(0.2766666667,0.8266666667))
pot.close();color(0.47,0.59,0.49).setFill();pot.fill()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
