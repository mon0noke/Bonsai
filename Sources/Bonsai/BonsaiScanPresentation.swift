import SwiftUI
import AppKit
import BonsaiCore

/// Clean's dedicated scan stage: anchored artwork, measured totals, one current location.
struct BonsaiScanPresentation:View {
    let scene:NatureScene
    let progress:String
    let allocated:UInt64?
    let cancel:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.bonsaiMotionSuppressed) private var suppressed
    var body:some View {
        GeometryReader {geometry in
            let size=BonsaiActivityMotion.scanPortraitSize(height:geometry.size.height,width:geometry.size.width)
            VStack(spacing:0) {
                ZStack {
                    BotanicalTimeline {time in
                        Ellipse().fill(Palette.accent.opacity(0.025+0.015*(sin(time*0.8)+1)/2))
                            .frame(width:size*0.85,height:size*0.64).blur(radius:35).offset(y:-size*0.05)
                    }
                    NatureIllustration(scene:scene,scanning:true)
                }.frame(width:size,height:size).offset(x:scene == .oak ? -size*0.038603 : 0)
                    .accessibilityHidden(true)
                Text(allocated.map {"Scanning · "+bytes($0)} ?? "Scanning your Mac")
                    .font(.system(size:28,weight:.semibold,design:.rounded)).monospacedDigit()
                    .padding(.top,25).lineLimit(1).minimumScaleFactor(0.75)
                    .help("Allocated bytes measured so far, including items that may need review. The total is not the amount selected for cleanup.")
                HStack(spacing:8) {
                    Circle().fill(Palette.accent).frame(width:5,height:5)
                    Text(location).font(.system(size:12)).foregroundStyle(Palette.muted)
                        .lineLimit(1).truncationMode(.middle)
                        .contentTransition(.opacity)
                        .animation(reduced || suppressed ? nil : .easeOut(duration:0.18),value:location)
                }.frame(height:22).padding(.top,10)
            }.frame(width:min(580,max(0,geometry.size.width-48)))
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.center)
                .onExitCommand(perform:cancel)
        }
    }
    private var location:String {
        progress.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path+"/",with:"~/")
    }
}
