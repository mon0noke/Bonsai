import AppKit
import Foundation

// Inspect the exported pixels, including every formerly transparent corner.
// A tile masked before macOS's own compositor can introduce a second backing.
let urls=[URL(fileURLWithPath:"outputs/Bonsai-Icon.png")]+(try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:"work/Bonsai.iconset"),includingPropertiesForKeys:nil)).filter {$0.pathExtension=="png"}
var checked=0
for url in urls {
    guard let image=NSBitmapImageRep(data:try Data(contentsOf:url)),let data=image.bitmapData else {fatalError("Unreadable icon: "+url.path)}
    precondition(image.bitsPerSample==8 && !image.isPlanar)
    if image.hasAlpha {
        let alpha=image.bitmapFormat.contains(.alphaFirst) ? 0 : image.samplesPerPixel-1
        for y in 0..<image.pixelsHigh {for x in 0..<image.pixelsWide {
            precondition(data[y*image.bytesPerRow+x*image.samplesPerPixel+alpha]==255,"Transparent export would expose macOS's second icon backing")
            checked+=1
        }}
    }
    for (x,y) in [(0,0),(image.pixelsWide-1,0),(0,image.pixelsHigh-1),(image.pixelsWide-1,image.pixelsHigh-1)] {
        let color=image.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
        precondition(color.redComponent>0.90 && color.greenComponent>0.87 && color.blueComponent>0.78,"Corner must belong to the ivory canvas, not a separate gray tile")
    }
}
print("PASS: \(urls.count) exported icon representations; \(checked) alpha pixels fully opaque; all corners ivory.")
