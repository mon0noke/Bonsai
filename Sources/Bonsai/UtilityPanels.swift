import SwiftUI
import AppKit

struct UtilityHeader:View {
    var title:String;var subtitle:String="";var onClose:()->Void
    var body:some View {
        HStack(alignment:.top,spacing:18) {
            VStack(alignment:.leading,spacing:8) {
                Text(title).font(.system(size:24,weight:.bold,design:.serif))
                if !subtitle.isEmpty {Text(subtitle).font(.system(size:12)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)}
            }
            Spacer(minLength:0)
            Button(action:onClose) {Image(systemName:"xmark").font(.system(size:13,weight:.semibold))}
                .buttonStyle(QuietIconStyle()).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close "+title)
        }
    }
}
struct AboutBonsaiView:View {
    var onClose:()->Void
    private var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown"}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top,spacing:15) {
                BonsaiGlyph().frame(width:82,height:82).clipShape(Circle()).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:8) {
                    HStack(alignment:.firstTextBaseline,spacing:10) {Text("Bonsai").font(.system(size:30,weight:.bold,design:.serif));Text("v"+version).font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.muted)}
                    Text("A little space. A little calm.\nCare for what matters.").font(.system(size:12,design:.serif)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
                Button(action:onClose) {Image(systemName:"xmark").font(.system(size:13,weight:.semibold))}.buttonStyle(QuietIconStyle()).handCursor().keyboardShortcut(.cancelAction).accessibilityLabel("Close About Bonsai")
            }.padding(.bottom,30)
            ForEach([NatureScene.oak,.elm,.maple,.pine,.olive],id:\.self) {scene in
                HStack(spacing:24) {
                    NatureIllustration(scene:scene).frame(width:76,height:76).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:6) {
                        Text(scene.name).font(.system(size:16,weight:.semibold,design:.serif)).foregroundStyle(color(scene))
                        Text(scene.verse).font(.system(size:12,design:.serif)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:0)
                }.frame(maxHeight:.infinity)
            }
        }.padding(32).foregroundStyle(Palette.text).accessibilityElement(children:.contain).accessibilityLabel("About Bonsai")
    }
    private func color(_ scene:NatureScene)->Color {scene == .oak ? Palette.accent:scene == .maple ? Color(red:0.85,green:0.57,blue:0.34):Palette.sage}
}
