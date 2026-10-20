import AppKit
// Package the original Bonsai artwork at native macOS icon resolutions.
let destination=CommandLine.arguments[1]
let source=URL(fileURLWithPath:"Resources/BonsaiIcon.png")
guard let image=NSImage(contentsOf:source) else {fatalError("Bonsai icon artwork missing")}
try FileManager.default.createDirectory(atPath:destination,withIntermediateDirectories:true)
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep);NSGraphicsContext.current?.imageInterpolation = .high
    // One opaque background lets macOS apply its icon shape without adding
    // a second-colored backing behind an inset transparent tile.
    NSColor(deviceRed:247.0/255,green:242.0/255,blue:227.0/255,alpha:1).setFill()
    NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
    image.draw(in:NSRect(x:0,y:0,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination).appendingPathComponent(name+".png"))
}
