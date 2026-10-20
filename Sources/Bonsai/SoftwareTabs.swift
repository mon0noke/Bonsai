import SwiftUI
import AppKit

/// One moving selection surface; each label is drawn once.
struct SoftwareTabs:View {
    @Binding var selection:String
    @ViewState private var hovered:String?
    @FocusState private var focused:String?
    @ViewState private var keyboardFocusVisible=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    var accessibilityTitle="Software section"
    var compact=false
    var tint:Color=Palette.sage
    var neutralSelection=false
    var roomy=false
    var fitLabels=false
    var selectionFill:Color?=nil
    var tabs:[(String,String)] = [("Uninstall","trash"),("Updates","arrow.down.circle"),("Startup","sunrise")]
    private var width:CGFloat {compact ? max(48,tabs.map {ceil(($0.0 as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:roomy ? 13:12,weight:.semibold)]).width)+20}.max() ?? 48):104}
    private func tabWidth(_ title:String)->CGFloat {
        fitLabels ? max(48,ceil((title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:roomy ? 13:12,weight:.semibold)]).width)+20) : width
    }
    private var height:CGFloat {roomy ? 36 : compact ? 24:36}
    private let gap:CGFloat=2
    private var selectedIndex:Int { tabs.firstIndex(where:{$0.0==selection}) ?? 0 }
    private var offset:CGFloat { tabs.prefix(selectedIndex).reduce(CGFloat.zero) {$0+tabWidth($1.0)+gap} }
    private var travel:Animation? { BonsaiNavigationMotion.animation(reduceMotion:reduceMotion) }
    var body:some View {
        ZStack(alignment:.leading) {
            selectionSurface
                .offset(x:offset).animation(travel,value:selection)
                .allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing:gap) {
                ForEach(tabs,id:\.0) { title,symbol in tab(title,symbol:symbol) }
            }
        }.padding(3).background(tint.opacity(0.065),in:Capsule(style:.continuous))
        .overlay(Capsule(style:.continuous).strokeBorder(contrast == .increased ? Palette.text.opacity(0.45) : tint.opacity(0.14)))
        .opacity(enabled ? 1 : 0.4)
        .accessibilityElement(children:.contain).accessibilityLabel(accessibilityTitle)
        .onKeyPress(.tab) {keyboardFocusVisible=true;return .ignored}
        .onKeyPress(.leftArrow) { move(-1);return .handled }
        .onKeyPress(.rightArrow) { move(1);return .handled }
        .onDisappear { hovered=nil }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in hovered=nil }
    }
    private var selectionSurface:some View {
        Capsule(style:.continuous)
            .fill(neutralSelection ? Color.white : (selectionFill ?? Palette.segment))
            .overlay(Capsule(style:.continuous).strokeBorder(tint.opacity(0.18)))
            .shadow(color:Palette.ink.opacity(scheme == .dark ? 0.18 : 0.10),radius:3,x:0,y:1)
            .frame(width:tabWidth(tabs[selectedIndex].0),height:height)
    }
    private func label(_ title:String,symbol:String,selectedLayer:Bool)->some View {
        HStack(spacing:5) {
            if !compact {Image(systemName:symbol).font(.system(size:12,weight:.medium))
                .frame(width:20,height:20)
                
                .accessibilityHidden(true)}
            Text(title).font(.system(size:roomy ? 13:12,weight:.semibold,design:roomy ? .rounded : compact ? .default : .monospaced)).lineLimit(1)
        }.foregroundStyle(selectedLayer ? (neutralSelection ? Palette.ink : Palette.text) : Palette.muted)
            .frame(width:tabWidth(title),height:height).contentShape(Capsule(style:.continuous))
    }
    private func tab(_ title:String,symbol:String)->some View {
        Button { keyboardFocusVisible=false;selection=title;focused=title } label: {
            label(title,symbol:symbol,selectedLayer:selection==title)
                .background(Capsule(style:.continuous).fill(tint.opacity(enabled && hovered==title && selection != title ? 0.10 : 0)))
        }.buttonStyle(SoftwareTabPressStyle()).handCursor()
        .focusable().focusEffectDisabled().focused($focused,equals:title)
        .overlay(Capsule(style:.continuous).stroke(keyboardFocusVisible && focused==title ? Palette.text.opacity(0.45) : .clear,lineWidth:1.5))
        .onHover { value in withAnimation(reduceMotion ? nil : .easeOut(duration:0.15)) { if value { hovered=title } else if hovered==title { hovered=nil } } }
        .accessibilityLabel(title).accessibilityValue(selection==title ? "Selected" : "")
        .accessibilityAddTraits(selection==title ? .isSelected : [])
    }
    private func move(_ step:Int) {
        guard enabled,!tabs.isEmpty else {return}
        let title=tabs[(selectedIndex+step+tabs.count)%tabs.count].0
        keyboardFocusVisible=true;selection=title;focused=title
    }
}
private struct SoftwareTabPressStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {configuration.label}
}
