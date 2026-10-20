import SwiftUI
import AppKit

/// macOS 14 fallback only. A single owner avoids paired push/pop calls and stops
/// a disappearing button from resetting a newer button's cursor.
@MainActor final class LegacyHandCursor {
    static let shared=LegacyHandCursor()
    private(set) var owner:UUID?
    private let apply:(Bool)->Void
    init(apply:@escaping (Bool)->Void = { hand in
        if hand { NSCursor.pointingHand.set() }
        else if NSCursor.current == .pointingHand { NSCursor.arrow.set() }
    }) { self.apply=apply }
    func update(id:UUID,active:Bool,enabled:Bool) {
        if active && enabled { owner=id;apply(true) }
        else { release(id:id) }
    }
    func release(id:UUID) {
        guard owner == id else { return }
        owner=nil;apply(false)
    }
}

@MainActor private struct HandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @CursorViewState private var id=UUID()
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0,*) {
            // Let SwiftUI own cursor hit testing and restoration. A decorative
            // NSView overlay is not reliable inside its hosting hierarchy.
            content.pointerStyle(enabled ? .link : .default)
        } else {
            content.onContinuousHover { phase in
                switch phase {
                case .active: LegacyHandCursor.shared.update(id:id,active:true,enabled:enabled)
                case .ended: LegacyHandCursor.shared.release(id:id)
                }
            }
            .onChange(of:enabled) { _,value in if !value { LegacyHandCursor.shared.release(id:id) } }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in LegacyHandCursor.shared.release(id:id) }
            .onDisappear { LegacyHandCursor.shared.release(id:id) }
        }
    }
}
extension View {
    func handCursor() -> some View { modifier(HandCursorModifier()) }
}

// Alias avoids the prerelease SDK State macro/property-wrapper collision.
private typealias CursorViewState<Value> = SwiftUI.State<Value>
