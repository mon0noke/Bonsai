import SwiftUI
import AppKit
import BonsaiCore


struct BonsaiBackground:View {
    var page:AppModel.Page = .clean
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var top:Color {Self.pageColor(page,scheme)}
    static func pageColor(_ page:AppModel.Page,_ scheme:ColorScheme)->Color {
        if scheme == .dark {
            switch page {
            case .clean:return Color(red:0.27,green:0.20,blue:0.24)
            case .software:return Color(red:0.23,green:0.28,blue:0.23)
            case .optimize:return Color(red:0.30,green:0.23,blue:0.19)
            case .analyze:return Color(red:0.17,green:0.28,blue:0.23)
            case .status:return Color(red:0.20,green:0.27,blue:0.25)
            }
        }
        switch page {
        case .clean:return Color(red:0.97,green:0.85,blue:0.88)
        case .software:return Color(red:0.87,green:0.92,blue:0.83)
        case .optimize:return Color(red:0.98,green:0.87,blue:0.77)
        case .analyze:return Color(red:0.82,green:0.91,blue:0.85)
        case .status:return Color(red:0.85,green:0.92,blue:0.89)
        }
    }
    var body:some View {
        ZStack {
            LinearGradient(colors:opaque ? [Palette.background,Palette.background] : [top,Palette.background],startPoint:.top,endPoint:.bottom)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

/// Flat surfaces keep controls consistent across macOS versions.
struct GlassSurface:ViewModifier {
    var radius:CGFloat=24
    var tint:Color = .white.opacity(0.035)
    var interactive=true
    var frosted=false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.background {
            if frosted && !opaque {RoundedRectangle(cornerRadius:radius).fill(.ultraThinMaterial)}
            else {RoundedRectangle(cornerRadius:radius).fill(Palette.raised)}
        }
            .overlay(RoundedRectangle(cornerRadius:radius).stroke(contrast == .increased ? Palette.text.opacity(0.4) : Palette.line).allowsHitTesting(false))
    }
}
struct GlassControls<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {content}
}
enum BonsaiNavigationMotion {
    static func animation(reduceMotion:Bool)->Animation? {reduceMotion ? nil : .spring(response:0.24,dampingFraction:0.90)}
}
struct PrimaryAction:ViewModifier {
    func body(content:Content) -> some View { content.buttonStyle(BonsaiPrimaryButtonStyle()) }
}
private struct BonsaiControlTintKey:EnvironmentKey {static let defaultValue=Palette.sage}
extension EnvironmentValues {
    var bonsaiControlTint:Color {
        get {self[BonsaiControlTintKey.self]}
        set {self[BonsaiControlTintKey.self]=newValue}
    }
}
/// Shared botanical surface for actions, fields and icon buttons. Hover changes
/// ink and fill without moving the layout; Reduce Motion removes all travel.
struct BonsaiControlSurface:ViewModifier {
    @Environment(\.bonsaiControlTint) private var tint
    var pressed=false
    var prominent=false
    @ViewState private var hovered=false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var windowState
    private var active:Bool {enabled && hovered && windowState != .inactive}
    func body(content:Content)->some View {
        content
            .background {
                Capsule(style:.continuous)
                    .fill(prominent ? Palette.accent.opacity(pressed && enabled ? 0.82 : 1) : tint.opacity(pressed && enabled ? 0.16 : active ? 0.10 : 0.045))
            }
            .overlay {
                Capsule(style:.continuous).strokeBorder(
                    contrast == .increased ? Palette.text.opacity(0.55) : tint.opacity(active ? 0.28 : 0.12),lineWidth:1).allowsHitTesting(false)
            }
            .contentShape(Capsule(style:.continuous))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:active)
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:pressed)
            .onHover {hovered=$0}
            .onDisappear {hovered=false}
            .onChange(of:windowState) {_,state in if state == .inactive {hovered=false}}
    }
}
struct BonsaiPrimaryButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:14,weight:.semibold)).padding(.horizontal,18).padding(.vertical,9)
            .foregroundStyle(Palette.ink)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed,prominent:true))
    }
}
struct SoftCapsuleStyle:ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:12,weight:.semibold)).padding(.horizontal,12).frame(height:28)
            .foregroundStyle(Palette.sage)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
    }
}
struct QuietTextStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hovered=false
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:12,weight:.medium))
            .foregroundStyle(hovered || configuration.isPressed ? Palette.sage : Palette.muted)
            .opacity(enabled ? 1 : 0.4).contentShape(Rectangle())
            .onHover {hovered=$0}
    }
}
struct QuietIconStyle:ButtonStyle {
    @Environment(\.bonsaiControlTint) private var tint
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:11,weight:.medium)).frame(width:28,height:28).foregroundStyle(tint)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
    }
}
struct QuietSegments<Value:Hashable>:View {
    var label:String; var options:[(Value,String)]; @Binding var selection:Value
    @FocusState private var focused:Value?
    @Namespace private var selectionMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        HStack(spacing:2) { ForEach(options,id:\.0) { value,title in
            Button { selection=value } label: { Text(title).font(.system(size:13,weight:.semibold)).foregroundStyle(selection==value ? Palette.text : Palette.muted).padding(.horizontal,14).padding(.vertical,8).background { if selection==value { Capsule().fill(Palette.segment).overlay(Capsule().stroke(Palette.line)).matchedGeometryEffect(id:"selected-segment",in:selectionMotion) } }.contentShape(Capsule()) }.handCursor().buttonStyle(.plain).focusable().focusEffectDisabled().focused($focused,equals:value).overlay(Capsule().stroke(focused==value ? Palette.text.opacity(0.45) : .clear,lineWidth:1.5)).accessibilityLabel(title).accessibilityValue(selection==value ? "Selected" : "").accessibilityAddTraits(selection==value ? .isSelected : [])
        } }.padding(3).bonsaiGlass(radius:100).animation(reduceMotion ? nil : .smooth(duration:0.32),value:selection).accessibilityElement(children:.contain).accessibilityLabel(label).onKeyPress(.leftArrow) { move(-1);return .handled }.onKeyPress(.rightArrow) { move(1);return .handled }
    }
    private func move(_ step:Int) { guard !options.isEmpty,let index=options.firstIndex(where:{$0.0==selection}) else { return };let next=options[(index+step+options.count)%options.count].0;selection=next;focused=next }
}
struct BonsaiSearchField:View {
    var prompt:String; @Binding var text:String
    var focusesOnAppear=false
    @FocusState private var focused:Bool
    var body:some View { HStack(spacing:8) { Image(systemName:"magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true); TextField(prompt,text:$text).textFieldStyle(.plain).accessibilityLabel(prompt).focused($focused) }.font(.system(size:12)).padding(.horizontal,11).frame(height:30).background(Palette.card,in:Capsule()).overlay(Capsule().stroke(Palette.line))
        .task {if focusesOnAppear {await Task.yield();focused=true}}
    }
}

struct BonsaiMark:View {
    var body:some View { BonsaiGlyph().aspectRatio(1,contentMode:.fit).accessibilityLabel("Bonsai emblem") }
}
/// The same bundled master supplies navigation, Dock and About artwork.
struct BonsaiGlyph:View {
    private static let artwork:NSImage? = Bundle.main.url(forResource:"BonsaiIcon",withExtension:"png").flatMap {NSImage(contentsOf:$0)}
    var body:some View {
        Group {
            if let image=Self.artwork {Image(nsImage:image).resizable().interpolation(.high).scaledToFit()}
            else {Image(systemName:"tree.fill").resizable().scaledToFit().foregroundStyle(Palette.sage)}
        }.accessibilityHidden(true)
    }
}
/// A bounded hover highlight; the fixed hit target keeps pointer entry stable.
struct NavigationTreeEmblem:View {
    var hovered:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        BonsaiGlyph()
            .frame(width:32,height:32)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(
                    LinearGradient(colors:[Color.white.opacity(0.95),Palette.sage.opacity(0.85)],startPoint:.topLeading,endPoint:.bottomTrailing),
                    lineWidth:1.4
                ).opacity(hovered ? 1:0)
                    .shadow(color:Palette.sage.opacity(hovered ? 0.55:0),radius:2)
            }
            .shadow(color:Palette.sage.opacity(hovered ? 0.3:0),radius:2)
            .shadow(color:Color.black.opacity(hovered ? 0.18:0),radius:1,x:0,y:1)
            .scaleEffect(hovered ? 1.08:1)
            .animation(reduceMotion ? nil:.easeInOut(duration:0.2),value:hovered)
            // The rail has a 40-point circle around this fixed 32-point button.
            // Bound the glow as well as the artwork, without clipping the rail.
            .frame(width:40,height:40).clipShape(Circle())
            .frame(width:32,height:32)
            .accessibilityHidden(true)
    }
}
struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    @Environment(\.colorSchemeContrast) private var contrast
    var body:some View { VStack(alignment:.leading,spacing:0) { content }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Palette.card,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(contrast == .increased ? Palette.text.opacity(0.4) : Palette.line)) }
}
struct Pill:View { var text:String;var color:Color=Palette.accent
    var body:some View { HStack(spacing:5) { Circle().fill(color).frame(width:4,height:4);Text(text).font(.system(size:10,weight:.medium)) }.padding(.horizontal,9).padding(.vertical,5).foregroundStyle(color).background(color.opacity(0.07),in:Capsule()) }
}
struct PageHeading:View { var eyebrow:String;var title:String;var detail:String
    var body:some View { VStack(alignment:.leading,spacing:7) { Text(title).font(.system(size:24,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity,alignment:.leading) }
}
struct EmptyState:View { var symbol:String;var title:String;var detail:String
    var body:some View { VStack(spacing:16) { Image(systemName:symbol).font(.system(size:30,weight:.ultraLight)).foregroundStyle(Palette.accent);Text(title).font(.system(size:18,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).frame(maxWidth:420) }.frame(maxWidth:.infinity).padding(40) }
}
struct Sparkline:View { var values:[Double];var color:Color=Palette.accent;var ceiling:Double=100
    var body:some View { GeometryReader { g in Path { p in let maxValue=max(ceiling,values.max() ?? 1);for (i,v) in values.enumerated() { let pt=CGPoint(x:g.size.width*Double(i)/Double(max(1,values.count-1)),y:g.size.height*(1-min(1,max(0,v/maxValue))));if i==0 { p.move(to:pt) } else { p.addLine(to:pt) } } }.stroke(color,style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round)) }.accessibilityLabel("History, up to 60 samples") }
}
struct QuietSurface:ViewModifier {
    var radius:CGFloat
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content) -> some View {
        content.background(opaque ? Palette.raised : Palette.card,in:RoundedRectangle(cornerRadius:radius)).overlay(RoundedRectangle(cornerRadius:radius).stroke(contrast == .increased ? Palette.text.opacity(0.4) : Palette.line))
    }
}
extension View {
    func secondaryText() -> some View { self.font(.system(size:12)).foregroundStyle(Palette.muted) }
    func bonsaiGlass(radius:CGFloat=24,tint:Color = .white.opacity(0.035),interactive:Bool=true,frosted:Bool=false) -> some View { modifier(GlassSurface(radius:radius,tint:tint,interactive:interactive,frosted:frosted)) }
    func bonsaiPrimary() -> some View { modifier(PrimaryAction()) }
    func quietSurface(radius:CGFloat=14) -> some View { self.modifier(QuietSurface(radius:radius)) }
}
// Explicit property-wrapper alias avoids prerelease SDK State macro collisions.
typealias ViewState<Value> = SwiftUI.State<Value>

private struct BonsaiListHover:ViewModifier {
    @ViewState private var hovering=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content:Content)->some View {
        content.background(Palette.text.opacity(hovering ? 0.065:0),in:RoundedRectangle(cornerRadius:12))
            .onHover {value in withAnimation(reduceMotion ? nil:.easeOut(duration:0.12)) {hovering=value}}
            .onDisappear {hovering=false}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) {_ in hovering=false}
    }
}
extension View {func bonsaiListHover()->some View {modifier(BonsaiListHover())}}

/// Navigation retains the active page’s palette while lists and settings stay flat.
struct PageNavigationSurface:ViewModifier {
    var page:AppModel.Page
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.background(BonsaiBackground.pageColor(page,scheme),in:Capsule())
            .overlay(Capsule().stroke(contrast == .increased ? Palette.text.opacity(0.4):Palette.text.opacity(0.12)))
    }
}
struct BalanceReturnButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.medium)).foregroundStyle(Palette.sage)
            .padding(.horizontal,18).padding(.vertical,11)
            .modifier(BonsaiControlSurface(pressed:configuration.isPressed))
    }
}

/// Lists inherit the actual parent background, including its gradient position.
/// Repainting a page gradient inside a list would restart it and create a seam.
private struct BonsaiListSurface:ViewModifier {
    var radius:CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.overlay(RoundedRectangle(cornerRadius:radius).stroke(contrast == .increased ? Palette.text.opacity(0.4):Color.clear))
    }
}
extension View {func bonsaiListSurface(radius:CGFloat=14)->some View {modifier(BonsaiListSurface(radius:radius))}}

/// Animated switches inherit the local accent and retain Toggle accessibility.
struct BonsaiSwitchStyle:ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bonsaiControlTint) private var tint
    func makeBody(configuration:Configuration)->some View {
        Button {configuration.isOn.toggle()} label: {
            Capsule().fill(configuration.isOn ? tint.opacity(0.78) : Color(white:scheme == .dark ? 0.30:0.66).opacity(0.65))
                .overlay(Capsule().strokeBorder(Color.white.opacity(configuration.isOn ? 0.20:0.10)))
                .animation(.easeInOut(duration:reduceMotion ? 0:0.22),value:configuration.isOn)
                .overlay {
                    Circle().fill(Color(white:0.96)).frame(width:18,height:18)
                        .shadow(color:Color.black.opacity(0.16),radius:1.5,x:0,y:1)
                        .offset(x:configuration.isOn ? 11:-11)
                        .animation(reduceMotion ? nil:.spring(response:0.32,dampingFraction:0.72),value:configuration.isOn)
                }.frame(width:46,height:24).contentShape(Capsule())
        }.buttonStyle(BonsaiSwitchPressStyle(reduceMotion:reduceMotion)).opacity(enabled ? 1:0.4)
            .accessibilityRepresentation {
                Toggle(isOn:configuration.$isOn) {configuration.label}.toggleStyle(.switch)
            }
    }
}

private struct BonsaiSwitchPressStyle:ButtonStyle {
    var reduceMotion:Bool
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96:1)
            .animation(reduceMotion ? nil:.easeOut(duration:0.12),value:configuration.isPressed)
    }
}
