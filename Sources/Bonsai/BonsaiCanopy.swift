import SwiftUI
import BonsaiCore

/// The same realistic pine portrait as the main screens. Static canvases do no frame work; only the
/// brief, successful Trash response schedules frames, with no ambient timer.
struct BonsaiCanopy:View {
    let growth:Double
    var pruningStart:Date?=nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var pruningFinished=false
    var body:some View {
        Group {
            if let start=pruningStart,!reduceMotion,!pruningFinished {
                TimelineView(.animation(minimumInterval:1.0/60)) {timeline in
                    drawing(progress:BonsaiGrowth.pruningProgress(elapsed:timeline.date.timeIntervalSince(start)))
                }
            } else {drawing(progress:pruningStart == nil ? 0 : 1)}
        }.task(id:pruningStart) {
            pruningFinished=false
            guard let start=pruningStart,!reduceMotion else {return}
            let remaining=max(0,BonsaiGrowth.pruningDuration-Date().timeIntervalSince(start))
            do {try await Task.sleep(for:.seconds(remaining));pruningFinished=true} catch {}
        }
    }
    private func drawing(progress:Double)->some View {
        Canvas {context,size in
            guard let portrait=TreeArtwork.images[.pine] else {return}
            let image=context.resolve(Image(nsImage:portrait))
            let scale=min(size.width/400,size.height/400)
            context.translateBy(x:(size.width-400*scale)/2,y:(size.height-400*scale)/2)
            context.scaleBy(x:scale,y:scale)
            let rect=CGRect(x:30,y:14,width:340,height:340)
            // Narrow, overlapping clipped bands deform the same cached portrait.
            // The original texture, bark, needles and pot are retained unchanged.
            for row in 0..<64 {
                let y=Double(row)/64,height=rect.height/64
                let width=BonsaiGrowth.canopyScale(topY:y+1/128,growth:growth,pruning:progress)
                var band=context
                band.clip(to:Path(CGRect(x:0,y:rect.minY+Double(row)*height,width:400,height:height+0.4)))
                band.translateBy(x:200,y:0);band.scaleBy(x:width,y:1);band.translateBy(x:-200,y:0)
                band.draw(image,in:rect)
            }
            if progress>0 && progress<1 {
                for i in 0..<12 {
                    let p=progress,originX=95+Double((i*43)%210),originY=55+Double((i*29)%115)
                    let x=originX+sin(p*3.1+Double(i))*15,y=originY+p*p*110
                    var needle=context;needle.opacity=(1-p)*min(1,p*8)
                    needle.translateBy(x:x,y:y);needle.rotate(by:.radians(p*4+Double(i)))
                    var sprig=Path()
                    for offset in [-2.0,0,2] {sprig.move(to:CGPoint(x:-4,y:offset));sprig.addLine(to:CGPoint(x:4,y:offset+2))}
                    needle.stroke(sprig,with:.color(Color(red:0.47,green:0.58,blue:0.25)),style:StrokeStyle(lineWidth:0.8,lineCap:.round))
                }
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
