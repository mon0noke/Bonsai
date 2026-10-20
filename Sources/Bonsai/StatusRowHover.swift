import AppKit
import SwiftUI

/// Native row tracking also receives window mouse events: SwiftUI List can omit
/// tracking-area entry notifications for recycled or partially clipped rows.
struct StatusRowHover:NSViewRepresentable {
    @Binding var hovering:Bool
    var enabled=true
    func makeNSView(context:Context)->StatusRowTrackingView {let view=StatusRowTrackingView();view.changed={hovering=$0};view.enabled=enabled;return view}
    func updateNSView(_ view:StatusRowTrackingView,context:Context) {view.changed={hovering=$0};view.enabled=enabled;view.refreshPointer()}
    static func dismantleNSView(_ view:StatusRowTrackingView,coordinator:()) {view.stop()}
}
final class StatusRowTrackingView:NSView {
    var changed:((Bool)->Void)?
    var enabled=true {didSet {if enabled != oldValue {refreshPointer()}}}
    private var tracking:NSTrackingArea?
    private var movementMonitor:Any?
    private var resignObserver:NSObjectProtocol?
    private let cursorID=UUID()
    private var refreshQueued=false
    private var stopped=false
    private(set) var hovered=false
    var monitorsPointer:Bool {movementMonitor != nil}
    override var isFlipped:Bool {true}
    override init(frame:NSRect) {super.init(frame:frame);clipsToBounds=true}
    required init?(coder:NSCoder) {super.init(coder:coder);clipsToBounds=true}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard !stopped else {return}
        if let tracking {removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.mouseMoved,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area;refreshPointer()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        if let window {
            stopped=false
            window.acceptsMouseMovedEvents=true
            movementMonitor=NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.scrollWheel]) {[weak self] event in
                guard let self else {return event}
                if event.window === self.window {
                    self.refreshPointer(publishingImmediately:true,location:event.locationInWindow)
                    self.queueRefresh()
                } else {self.setHovered(false,publishingImmediately:true)}
                return event
            }
            resignObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main) {[weak self] _ in
                self?.setHovered(false,publishingImmediately:true)
            }
            updateTrackingAreas()
        } else {setHovered(false)}
    }
    override func layout() {super.layout();refreshPointer()}
    override func mouseEntered(with event:NSEvent) {refreshPointer(publishingImmediately:true,location:event.locationInWindow);queueRefresh()}
    override func mouseMoved(with event:NSEvent) {refreshPointer(publishingImmediately:true,location:event.locationInWindow);queueRefresh()}
    override func mouseExited(with event:NSEvent) {refreshPointer(publishingImmediately:true,location:event.locationInWindow)}
    func containsPointer(_ point:NSPoint)->Bool {enabled && bounds.contains(point) && visibleRect.contains(point) && !visibleRect.isEmpty}
    func refreshPointer(publishingImmediately:Bool=false,location:NSPoint?=nil) {
        guard enabled,!stopped,let window,window.isKeyWindow,!isHiddenOrHasHiddenAncestor else {setHovered(false,publishingImmediately:publishingImmediately);return}
        let active=containsPointer(convert(location ?? window.mouseLocationOutsideOfEventStream,from:nil))
        setHovered(active,publishingImmediately:publishingImmediately)
        // Reapply after SwiftUI handles this event so its native button cursor
        // cannot overwrite the row's hand. A single identity owns restoration.
        LegacyHandCursor.shared.update(id:cursorID,active:active,enabled:true)
    }
    private func queueRefresh() {
        guard !refreshQueued else {return};refreshQueued=true
        DispatchQueue.main.async {[weak self] in guard let self else {return};self.refreshQueued=false;guard !self.stopped else {return};self.refreshPointer(publishingImmediately:true)}
    }
    private func setHovered(_ value:Bool,publishingImmediately:Bool=false) {
        if !value {LegacyHandCursor.shared.release(id:cursorID)}
        guard hovered != value else {return};hovered=value
        if publishingImmediately {changed?(value)}
        else {
            // Layout must not publish state while SwiftUI is updating a view.
            DispatchQueue.main.async {[weak self] in guard let self,self.hovered==value else {return};self.changed?(value)}
        }
    }
    private func removeMonitor() {
        if let movementMonitor {NSEvent.removeMonitor(movementMonitor)};movementMonitor=nil
        if let resignObserver {NotificationCenter.default.removeObserver(resignObserver)};resignObserver=nil
    }
    func stop() {stopped=true;removeMonitor();if let tracking {removeTrackingArea(tracking)};tracking=nil;hovered=false;LegacyHandCursor.shared.release(id:cursorID);changed=nil}
}
