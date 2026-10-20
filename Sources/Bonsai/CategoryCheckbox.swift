import SwiftUI
import AppKit

/// A native three-state checkbox: partially chosen groups never look empty.
/// The model determines the state and click intent, rather than AppKit's cycle.
struct CategoryCheckbox: NSViewRepresentable {
    let selectedCount:Int
    let itemCount:Int
    let label:String
    let enabled:Bool
    let action:()->Void
    func makeCoordinator()->Coordinator {Coordinator(action:action)}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton()
        button.setButtonType(.switch)
        button.title=""
        button.allowsMixedState=true
        button.target=context.coordinator
        button.action=#selector(Coordinator.activate(_:))
        button.controlSize = .regular
        return button
    }
    func updateNSView(_ button:NSButton,context:Context) {
        context.coordinator.action=action
        button.state=selectedCount==0 ? .off : selectedCount==itemCount ? .on : .mixed
        button.isEnabled=enabled
        button.contentTintColor=NSColor(Palette.accent)
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp("\(selectedCount) of \(itemCount) selected. "+(selectedCount>0 ? "Click to clear this category." : "Click to select eligible items."))
        button.toolTip="\(selectedCount) of \(itemCount) selected"
    }
    final class Coordinator:NSObject {
        var action:()->Void
        init(action:@escaping ()->Void) {self.action=action}
        @objc func activate(_ sender:NSButton) {action()}
    }
}
