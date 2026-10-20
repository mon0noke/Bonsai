import SwiftUI
import AppKit

/// A vertical SwiftUI viewport with a native horizontal lock. Width constraints
/// alone do not disable AppKit's trackpad elasticity or horizontal clip origin.
/// The viewport reaches the containing panel edge; content stops before the
/// native indicator track in both overlay and always-visible scrollbar modes.
struct BonsaiScrollView<Content:View>:View {
    var edgeInset:CGFloat=0
    @ViewBuilder var content:Content
    var body:some View {
        GeometryReader {geometry in
            ScrollView(.vertical) {
                content.frame(width:max(0,geometry.size.width-max(18,edgeInset)),alignment:.topLeading)
                    .padding(.trailing,max(18,edgeInset))
                    .background(SettingsHorizontalLock().accessibilityHidden(true))
            }
        }.padding(.trailing,-edgeInset)
    }
}

struct SettingsScrollView<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {BonsaiScrollView(edgeInset:20) {content}}
}
private struct SettingsHorizontalLock:NSViewRepresentable {
    func makeNSView(context:Context)->SettingsHorizontalLockView {SettingsHorizontalLockView()}
    func updateNSView(_ view:SettingsHorizontalLockView,context:Context) {view.scheduleAttachment()}
    static func dismantleNSView(_ view:SettingsHorizontalLockView,coordinator:()) {view.detach()}
}
final class SettingsHorizontalLockView:NSView {
    private weak var scroll:NSScrollView?
    private var boundsObserver:NSObjectProtocol?
    private var originalElasticity:NSScrollView.Elasticity = .automatic
    private var originalHorizontalScroller=false
    private var originalBoundsNotifications=false
    private var attachmentQueued=false
    private var stopped=false
    private var adjustingBounds=false
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func viewDidMoveToSuperview() {super.viewDidMoveToSuperview();scheduleAttachment()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();if window==nil {detach()} else {stopped=false;scheduleAttachment()}}
    override func layout() {super.layout();scheduleAttachment()}
    func scheduleAttachment() {
        guard !stopped,!attachmentQueued else {return};attachmentQueued=true
        DispatchQueue.main.async {[weak self] in
            guard let self else {return};self.attachmentQueued=false;guard !self.stopped else {return}
            var ancestor=self.superview
            while let view=ancestor {
                if let scroll=view as? NSScrollView {self.attach(to:scroll);return}
                ancestor=view.superview
            }
        }
    }
    func attach(to target:NSScrollView) {
        guard !stopped else {return}
        if scroll !== target {
            restore();scroll=target
            originalElasticity=target.horizontalScrollElasticity
            originalHorizontalScroller=target.hasHorizontalScroller
            originalBoundsNotifications=target.contentView.postsBoundsChangedNotifications
            target.contentView.postsBoundsChangedNotifications=true
            boundsObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:target.contentView,queue:.main) {[weak self] _ in self?.lockHorizontalPosition()}
        }
        target.horizontalScrollElasticity = .none
        target.hasHorizontalScroller=false
        lockHorizontalPosition()
    }
    private func lockHorizontalPosition() {
        guard !adjustingBounds,let scroll else {return}
        let clip=scroll.contentView
        // Scaled SwiftUI viewports can have a fractional backing-pixel origin.
        // Leave that stable rounding alone instead of recursively fighting it.
        let pixel=1 / (window?.backingScaleFactor ?? 2)
        guard abs(clip.bounds.origin.x) > pixel else {return}
        // Preserve vertical position, including legitimate vertical elasticity.
        adjustingBounds=true
        defer {adjustingBounds=false}
        clip.setBoundsOrigin(NSPoint(x:0,y:clip.bounds.origin.y))
    }
    private func restore() {
        if let boundsObserver {NotificationCenter.default.removeObserver(boundsObserver)};boundsObserver=nil
        if let scroll {
            scroll.horizontalScrollElasticity=originalElasticity
            scroll.hasHorizontalScroller=originalHorizontalScroller
            scroll.contentView.postsBoundsChangedNotifications=originalBoundsNotifications
        }
        scroll=nil
    }
    func detach() {stopped=true;restore()}
}
