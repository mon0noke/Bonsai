import SwiftUI
import AppKit
import BonsaiCore

enum BonsaiNavigationAction:String,CaseIterable {
    case settings="Settings",doctor="Run Doctor",screenOn="Keep Screen On",cleanScreen="Clean Screen",about="About Bonsai",updates="Check for Updates"
    var symbol:String { switch self {
    case .settings:return "gearshape"
    case .doctor:return "stethoscope"
    case .screenOn:return "cup.and.saucer"
    case .cleanScreen:return "paintbrush"
    case .about:return "info.circle"
    case .updates:return "arrow.triangle.2.circlepath"
    } }
}

/// An anchored menu without the native popover arrow or extra title/dividers.
struct BonsaiDropdown:View {
    var keepAwake:Bool
    var perform:(BonsaiNavigationAction)->Void
    var dismiss:()->Void
    @FocusState private var focused:BonsaiNavigationAction?
    @ViewState private var hovered:BonsaiNavigationAction?
    @ViewState private var keyboard=false
    @ViewState private var keyboardSelection:BonsaiNavigationAction = .settings
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var menuItems:some View {
        VStack(spacing:0) { ForEach(BonsaiNavigationAction.allCases,id:\.self) { item in menuRow(item) } }
    }
    func menuRow(_ item:BonsaiNavigationAction) -> some View {
        let selected:Bool = (hovered == item) || (keyboard && (focused == item))
        let state:String = item == BonsaiNavigationAction.screenOn ? (keepAwake ? "On" : "Off") : ""
        let hint:String = item == BonsaiNavigationAction.updates ? "Review updates for installed applications" : item == BonsaiNavigationAction.screenOn ? "Toggle a one-hour display-sleep assertion" : item.rawValue
        return Button { perform(item) } label: { DropdownRowLabel(item:item,keepAwake:keepAwake,highlighted:selected) }.handCursor()
            .buttonStyle(.plain).focusable().focusEffectDisabled().focused($focused,equals:item)
            .onHover { inside in hovered=inside ? item : nil }
            .accessibilityLabel(item.rawValue).accessibilityValue(state).help(hint)
            .onKeyPress(.return) { perform(keyboardSelection);return .handled }
    }
    var body:some View {
        menuItems .padding(6).frame(width:180)
            .background { RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[Palette.raised,Palette.background].map { $0.opacity(opaque ? 1 : 0.92) },startPoint:.topLeading,endPoint:.bottomTrailing)).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)) }
            .overlay(RoundedRectangle(cornerRadius:16).stroke(LinearGradient(colors:[Palette.text.opacity(contrast == .increased ? 0.40 : 0.12),Palette.text.opacity(contrast == .increased ? 0.30 : 0.06)],startPoint:.top,endPoint:.bottom),lineWidth:0.6))
            .shadow(color:.black.opacity(0.16),radius:16,y:8)
            .accessibilityElement(children:.contain).accessibilityLabel("Bonsai menu")
            .onAppear { focused = .settings }
            .onKeyPress(.escape) { dismiss();return .handled }
            .onKeyPress(.downArrow) { move(1);return .handled }
            .onKeyPress(.upArrow) { move(-1);return .handled }
            .onKeyPress(.tab,phases:.down) { key in move(key.modifiers.contains(.shift) ? -1 : 1);return .handled }
            .onKeyPress(.return) { perform(keyboardSelection);return .handled }
    }
    private func move(_ step:Int) {
        keyboard=true;hovered=nil
        let items=BonsaiNavigationAction.allCases
        let index=items.firstIndex(of:keyboardSelection) ?? 0
        keyboardSelection=items[(index+step+items.count)%items.count]
        focused=keyboardSelection
    }
}

private struct DropdownRowLabel:View {
    let item:BonsaiNavigationAction
    let keepAwake:Bool
    let highlighted:Bool
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:item.symbol).font(.system(size:15,weight:.regular)).foregroundStyle(Palette.muted).frame(width:20).accessibilityHidden(true)
            Text(item.rawValue).font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.90).allowsTightening(true)
            Spacer(minLength:0)
            if item == .screenOn && keepAwake { Image(systemName:"checkmark").font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.accent).accessibilityHidden(true) }
        }.foregroundStyle(Palette.text).padding(.horizontal,8).frame(height:32).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            .background(highlighted ? Palette.sage.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:8))
    }
}
