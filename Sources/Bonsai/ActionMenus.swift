import SwiftUI
import AppKit

struct BonsaiMenuAction {
    let title:String
    let symbol:String
    var group=0
    var destructive=false
    var enabled=true
    let perform:()->Void
    init(_ title:String,_ symbol:String,group:Int=0,destructive:Bool=false,enabled:Bool=true,perform:@escaping ()->Void) {
        self.title=title;self.symbol=symbol;self.group=group;self.destructive=destructive;self.enabled=enabled;self.perform=perform
    }
}

/// Both secondary-click and ellipsis actions share this arrowless glass panel.
struct BonsaiActionMenu:View {
    let label:String
    let actions:[BonsaiMenuAction]
    var triggerHeight:CGFloat=30
    var body:some View {BonsaiMenuTrigger(label:label,actions:actions).frame(width:28,height:triggerHeight)}
}
private struct BonsaiMenuTrigger:NSViewRepresentable {
    let label:String
    let actions:[BonsaiMenuAction]
    @Environment(\.bonsaiMotionSuppressed) private var suppressed
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->BonsaiMenuButton {BonsaiMenuButton()}
    func updateNSView(_ button:BonsaiMenuButton,context:Context) {button.actions=actions;button.isEnabled=enabled && !suppressed;button.setAccessibilityLabel(label);button.toolTip=label}
}
private final class BonsaiMenuButton:NSButton {
    var actions:[BonsaiMenuAction]=[]
    init() {
        super.init(frame:.zero);target=self;action=#selector(openMenu)
        isBordered=false;imagePosition = .imageOnly
        image=NSImage(systemSymbolName:"ellipsis",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:13,weight:.semibold))
        contentTintColor = .secondaryLabelColor
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override var intrinsicContentSize:NSSize {NSSize(width:28,height:30)}
    override func resetCursorRects() {addCursorRect(bounds,cursor:.pointingHand)}
    @objc private func openMenu() {
        guard let window else {return}
        let anchor=window.convertToScreen(convert(bounds,to:nil))
        BonsaiMenuPresenter.shared.show(actions,at:NSPoint(x:anchor.maxX,y:anchor.minY-4),owner:window,alignRight:true)
    }
}

extension View {
    func bonsaiContextMenu(actions:[BonsaiMenuAction])->some View {
        background(BonsaiContextTargetView(actions:actions).accessibilityHidden(true))
            .accessibilityAction(named:Text("Show Actions")) {
                guard let owner=NSApp.mainWindow ?? NSApp.windows.first(where:{$0.isVisible && $0.canBecomeMain}) else {return}
                let pointer=NSEvent.mouseLocation
                let point=owner.frame.contains(pointer) ? pointer:NSPoint(x:owner.frame.midX,y:owner.frame.midY)
                BonsaiMenuPresenter.shared.show(actions,at:point,owner:owner)
            }
    }
}
private struct BonsaiContextTargetView:NSViewRepresentable {
    let actions:[BonsaiMenuAction]
    @Environment(\.bonsaiMotionSuppressed) private var suppressed
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->BonsaiContextTarget {let view=BonsaiContextTarget();view.actions=actions;view.interactive=enabled && !suppressed;return view}
    func updateNSView(_ view:BonsaiContextTarget,context:Context) {view.actions=actions;view.interactive=enabled && !suppressed}
    static func dismantleNSView(_ view:BonsaiContextTarget,coordinator:()) {BonsaiContextRegistry.shared.remove(view)}
}
private final class BonsaiContextTarget:NSView {
    var interactive=true
    var actions:[BonsaiMenuAction]=[]
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {BonsaiContextRegistry.shared.add(self)} else {BonsaiContextRegistry.shared.remove(self)}
    }
    func contains(_ event:NSEvent)->Bool {
        guard interactive,event.window === window,!isHiddenOrHasHiddenAncestor,!visibleRect.isEmpty else {return false}
        return visibleRect.contains(convert(event.locationInWindow,from:nil))
    }
}
private final class WeakContextTarget {weak var value:BonsaiContextTarget?;init(_ value:BonsaiContextTarget) {self.value=value}}
/// One event monitor serves all visible rows; child-file targets win over app rows.
private final class BonsaiContextRegistry {
    static let shared=BonsaiContextRegistry()
    private var targets:[WeakContextTarget]=[]
    private var monitor:Any?
    func add(_ view:BonsaiContextTarget) {
        targets.removeAll {$0.value==nil || $0.value === view};targets.append(WeakContextTarget(view))
        if monitor==nil {
            monitor=NSEvent.addLocalMonitorForEvents(matching:[.rightMouseDown,.leftMouseDown]) {[weak self] event in
                guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),let self else {return event}
                self.targets.removeAll {$0.value==nil}
                let matches=self.targets.compactMap(\.value).filter {$0.contains(event)}
                guard let target=matches.min(by:{$0.bounds.width*$0.bounds.height<$1.bounds.width*$1.bounds.height}),let owner=target.window else {return event}
                BonsaiMenuPresenter.shared.show(target.actions,at:NSEvent.mouseLocation,owner:owner)
                return nil
            }
        }
    }
    func remove(_ view:BonsaiContextTarget) {
        targets.removeAll {$0.value==nil || $0.value === view}
        if targets.isEmpty,let monitor {NSEvent.removeMonitor(monitor);self.monitor=nil}
    }
}
private final class BonsaiMenuSelection:ObservableObject {@Published var index:Int?}
private final class BonsaiMenuPanel:NSPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
    override func cancelOperation(_ sender:Any?) {BonsaiMenuPresenter.shared.dismiss()}
}
private final class BonsaiMenuPresenter {
    static let shared=BonsaiMenuPresenter()
    private var panel:BonsaiMenuPanel?
    private weak var owner:NSWindow?
    private var monitor:Any?
    private var inactiveObserver:NSObjectProtocol?
    private var closeObserver:NSObjectProtocol?
    private var selection=BonsaiMenuSelection()
    private var actions:[BonsaiMenuAction]=[]
    func show(_ actions:[BonsaiMenuAction],at point:NSPoint,owner:NSWindow,alignRight:Bool=false) {
        dismiss();guard !actions.isEmpty else {return}
        self.actions=actions;self.owner=owner;selection=BonsaiMenuSelection()
        let separators=actions.indices.filter {$0>0 && actions[$0].group != actions[$0-1].group}.count
        let size=NSSize(width:246,height:16+36*actions.count+13*separators)
        let screen=NSScreen.screens.first {$0.frame.contains(point)} ?? owner.screen ?? NSScreen.main
        let available=screen?.visibleFrame ?? NSRect(origin:.zero,size:size)
        let x=max(available.minX+6,min(point.x-(alignRight ? size.width:0),available.maxX-size.width-6))
        let y=max(available.minY+6,min(point.y-size.height,available.maxY-size.height-6))
        let popup=BonsaiMenuPanel(contentRect:NSRect(origin:NSPoint(x:x,y:y),size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        popup.title="Bonsai actions";popup.isOpaque=false;popup.backgroundColor = .clear;popup.hasShadow=true
        popup.level = .popUpMenu;popup.hidesOnDeactivate=true;popup.isReleasedWhenClosed=false
        popup.collectionBehavior=[.transient,.fullScreenAuxiliary,.ignoresCycle]
        popup.appearance=owner.effectiveAppearance
        let host=NSHostingView(rootView:BonsaiMenuSurface(actions:actions,selection:selection,pick:{[weak self] in self?.pick($0)}).bonsaiAppearance().compactInterface())
        host.frame=NSRect(origin:.zero,size:size);host.wantsLayer=true;host.layer?.cornerRadius=20;host.layer?.masksToBounds=true
        popup.contentView=host;panel=popup;owner.addChildWindow(popup,ordered:.above);popup.makeKeyAndOrderFront(nil)
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown,.scrollWheel]) {[weak self] event in
            guard let self,let panel=self.panel else {return event}
            if event.type == .keyDown,event.window === panel {
                switch event.keyCode {
                case 53:self.dismiss();return nil
                case 125:self.move(1);return nil
                case 126:self.move(-1);return nil
                case 36,76:if let index=self.selection.index {self.pick(index)};return nil
                default:break
                }
            }
            if event.window !== panel {self.dismiss()}
            return event
        }
        inactiveObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) {[weak self] _ in self?.dismiss()}
        closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:owner,queue:.main) {[weak self] _ in self?.dismiss()}
    }
    private func move(_ direction:Int) {
        let enabled=actions.indices.filter {actions[$0].enabled};guard !enabled.isEmpty else {return}
        let current=selection.index.flatMap {enabled.firstIndex(of:$0)} ?? (direction>0 ? -1:0)
        selection.index=enabled[(current+direction+enabled.count)%enabled.count]
    }
    private func pick(_ index:Int) {
        guard actions.indices.contains(index),actions[index].enabled else {return}
        let action=actions[index].perform;dismiss();DispatchQueue.main.async(execute:action)
    }
    func dismiss() {
        if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil
        if let inactiveObserver {NotificationCenter.default.removeObserver(inactiveObserver)};inactiveObserver=nil
        if let closeObserver {NotificationCenter.default.removeObserver(closeObserver)};closeObserver=nil
        if let panel {owner?.removeChildWindow(panel);panel.orderOut(nil);panel.close()}
        panel=nil;owner=nil;actions=[]
    }
}
private struct BonsaiMenuSurface:View {
    let actions:[BonsaiMenuAction]
    @ObservedObject var selection:BonsaiMenuSelection
    let pick:(Int)->Void
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            ForEach(actions.indices,id:\.self) {index in
                if index>0 && actions[index].group != actions[index-1].group {Rectangle().fill(Palette.text.opacity(0.10)).frame(height:1).padding(.horizontal,6).padding(.vertical,6)}
                let item=actions[index]
                Button {pick(index)} label: {
                    HStack(spacing:11) {
                        Image(systemName:item.symbol).font(.system(size:15,weight:.regular)).foregroundStyle(Palette.muted).frame(width:20).accessibilityHidden(true)
                        Text(item.title).font(.system(size:13,weight:.semibold,design:.rounded))
                        Spacer(minLength:0)
                    }.foregroundStyle(Palette.text).padding(.horizontal,9).frame(height:36).contentShape(RoundedRectangle(cornerRadius:9))
                        .background(Palette.text.opacity(selection.index==index ? 0.085:0),in:RoundedRectangle(cornerRadius:9))
                }.buttonStyle(.plain).handCursor().disabled(!item.enabled).opacity(item.enabled ? 1:0.4)
                    .onHover {inside in if inside && item.enabled {selection.index=index} else if selection.index==index {selection.index=nil}}
            }
        }.padding(8).frame(width:246)
            .background {RoundedRectangle(cornerRadius:20).fill(Palette.raised.opacity(opaque ? 1:0.56)).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20))}
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Palette.text.opacity(0.14),lineWidth:0.7))
            .accessibilityElement(children:.contain).accessibilityLabel("Bonsai actions")
    }
}
func bonsaiCopy(_ text:String) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)}
