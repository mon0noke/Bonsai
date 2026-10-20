import SwiftUI

/// Equal hit areas and a quiet hover surface keep the review header uncluttered.
struct CleanToolbarStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        CleanToolbarSurface(label:configuration.label,pressed:configuration.isPressed,enabled:enabled,reduceMotion:reduceMotion)
    }
}
private struct CleanToolbarSurface<Label:View>:View {
    var label:Label
    var pressed:Bool
    var enabled:Bool
    var reduceMotion:Bool
    @ViewState private var hovering=false
    var body:some View {
        label.font(.system(size:15,weight:.semibold)).frame(width:36,height:36)
            .foregroundStyle(Palette.text.opacity(enabled ? (hovering ? 1 : 0.72) : 0.30))
            .background(Palette.text.opacity(enabled ? (hovering ? 0.085 : 0.035) : 0.02),in:Circle())
            .contentShape(Circle()).onHover {hovering=$0}
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:hovering)
            .animation(reduceMotion ? nil : .easeOut(duration:0.10),value:pressed)
    }
}

/// Hide the native Menu indicator at the call site; this label owns its one arrow.
struct CleanMenuLabel:View {
    var title:String
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hovering=false
    var body:some View {
        HStack(spacing:7) {
            Text(title).font(.system(size:12,weight:.medium))
            Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold)).accessibilityHidden(true)
        }.foregroundStyle(Palette.muted.opacity(enabled ? 1 : 0.35))
            .padding(.horizontal,10).frame(height:30)
            .background(Palette.text.opacity(hovering && enabled ? 0.06 : 0),in:Capsule())
            .contentShape(Capsule()).onHover {hovering=$0}
    }
}
