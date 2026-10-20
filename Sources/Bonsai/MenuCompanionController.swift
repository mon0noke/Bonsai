import AppKit
import SwiftUI
import Combine
import BonsaiCore

/// One status item and one shared model; changing preferences never starts another sampler.
@MainActor final class MenuCompanionController:NSObject {
    private var item:NSStatusItem?
    private var panel:BonsaiMenuPanel?
    private var localMonitor:Any?
    private var globalMonitor:Any?
    private var subscriptions=Set<AnyCancellable>()
    private var preferences:NSObjectProtocol?
    private weak var model:AppModel?
    var openMain:()->Void={}
    init(model:AppModel) {
        self.model=model;super.init()
        model.$snapshot.receive(on:RunLoop.main).sink {[weak self] _ in self?.refresh()}.store(in:&subscriptions)
        model.$keepAwake.receive(on:RunLoop.main).sink {[weak self] _ in self?.refresh()}.store(in:&subscriptions)
        preferences=NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.refresh()}}
        refresh()
    }
    func refresh() {
        guard let model else {return}
        let defaults=UserDefaults.standard
        guard defaults.object(forKey:"menuBarVisible") as? Bool != false else {closePanel();if let item {NSStatusBar.system.removeStatusItem(item)};item=nil;return}
        if item==nil {
            item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
            item?.button?.target=self;item?.button?.action=#selector(clicked)
            item?.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        }
        let display=defaults.string(forKey:"menuBarDisplay") ?? "Both"
        let awakeIcon=model.keepAwake && defaults.object(forKey:"awakeIcon") as? Bool != false
        item?.button?.image=NSImage(systemSymbolName:awakeIcon ? "cup.and.saucer.fill":"tree.fill",accessibilityDescription:awakeIcon ? "Keep Screen On active":"Bonsai")
        if display=="CPU" && !awakeIcon {item?.button?.image=nil}
        item?.button?.title=display=="Tree" ? "" : " "+(model.snapshot.cpu.map {String(format:"%.0f%%",$0)} ?? "—")
        item?.button?.imagePosition = .imageLeading
        item?.button?.setAccessibilityLabel("Bonsai menu bar")
        item?.button?.toolTip="Bonsai · "+HealthAssessment.evaluate(model.snapshot).title
    }
    @objc private func clicked() {
        let right=NSApp.currentEvent?.type == .rightMouseUp
        let swap=UserDefaults.standard.bool(forKey:"swapMenuClicks")
        if right != swap {showMenu()} else {togglePanel()}
    }
    func togglePanel() {
        if panel?.isVisible==true {closePanel();return}
        guard let button=item?.button,let anchorWindow=button.window,let model else {return}
        let anchor=anchorWindow.convertToScreen(button.convert(button.bounds,to:nil))
        let screen=anchorWindow.screen ?? NSScreen.screens.first {$0.frame.contains(CGPoint(x:anchor.midX,y:anchor.midY))} ?? NSScreen.main
        guard let screen else {return}
        let view=CompanionView(closePanel:{[weak self] in self?.closePanel()},openMain:{[weak self] in self?.openMain()}).environmentObject(model).compactInterface().clipShape(RoundedRectangle(cornerRadius:18))
        let host=NSHostingController(rootView:view)
        let size=host.view.fittingSize
        let frame=MenuPanelPlacement.frame(anchor:anchor,visible:screen.visibleFrame,size:size)
        let window=BonsaiMenuPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.contentViewController=host;window.isReleasedWhenClosed=false
        window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=true
        window.level = .popUpMenu;window.isFloatingPanel=true;window.hidesOnDeactivate=false
        window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
        window.setFrame(frame,display:false);panel=window
        // A nonactivating panel follows the clicked menu item to the active Space;
        // bringing the main application forward would switch out of full screen.
        window.makeKeyAndOrderFront(nil);window.orderFrontRegardless()
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) {[weak self,weak window] event in
            if event.type == .keyDown,event.keyCode==53,event.window===window {self?.closePanel();return nil}
            if event.type != .keyDown,event.window !== window,event.window !== anchorWindow {self?.closePanel()}
            return event
        }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) {[weak self] _ in self?.closePanel()}
    }
    func closePanel() {
        panel?.orderOut(nil);panel=nil
        if let localMonitor {NSEvent.removeMonitor(localMonitor)};localMonitor=nil
        if let globalMonitor {NSEvent.removeMonitor(globalMonitor)};globalMonitor=nil
    }

    private func showMenu() {
        closePanel()
        let menu=NSMenu()
        for (title,selector) in [("Open Bonsai",#selector(open)),("Settings…",#selector(settings)),("Run Doctor",#selector(doctor)),("Keep Screen On",#selector(awake)),("Clean Screen",#selector(cleanScreen)),("Quit Bonsai",#selector(quit))] {
            let row=NSMenuItem(title:title,action:selector,keyEquivalent:"");row.target=self
            if selector == #selector(awake) {row.state=model?.keepAwake == true ? .on:.off}
            menu.addItem(row)
        }
        item?.menu=menu;item?.button?.performClick(nil);item?.menu=nil
    }
    @objc private func open() {closePanel();openMain()}
    @objc private func settings() {model?.requestedUtility="settings";open()}
    @objc private func doctor() {model?.requestedUtility="doctor";open()}
    @objc private func awake() {guard let model else {return};if model.keepAwake {model.awake(false)} else {model.awakeFor(3600)}}
    @objc private func cleanScreen() {model?.screen.toggle()}
    @objc private func quit() {model?.shutdown();NSApp.terminate(nil)}
    func stop() {closePanel();if let item {NSStatusBar.system.removeStatusItem(item)};item=nil;if let preferences {NotificationCenter.default.removeObserver(preferences)};subscriptions=[]}
}
extension Notification.Name {static let bonsaiUtility=Notification.Name("BonsaiUtility");static let bonsaiOpenMain=Notification.Name("BonsaiOpenMain")}

private final class BonsaiMenuPanel:NSPanel {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {false}
}
