import AppKit
import SwiftUI

@main struct SettingsScrollChecks {
    @MainActor static func main() {
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ title:String) {checks+=1;guard value else {fatalError("FAIL: "+title)};print("PASS "+title)}
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:540,height:320))
        scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
        scroll.horizontalScrollElasticity = .allowed
        let document=NSView(frame:NSRect(x:0,y:0,width:980,height:1600));scroll.documentView=document
        let lock=SettingsHorizontalLockView();document.addSubview(lock);lock.attach(to:scroll)
        check(scroll.horizontalScrollElasticity == .none,"Horizontal elasticity disabled")
        check(!scroll.hasHorizontalScroller,"Horizontal scrollbar disabled")
        for delta in [-180.0,180.0,24.0] {
            scroll.contentView.setBoundsOrigin(NSPoint(x:delta,y:240))
            check(scroll.contentView.bounds.origin.x == 0,"Horizontal offset \(delta) is synchronously clamped")
            check(scroll.contentView.bounds.origin.y == 240,"Vertical position is preserved")
        }
        var reentrantNotifications=0
        let observer=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) {_ in
            reentrantNotifications+=1
            if scroll.contentView.bounds.origin.x == 0 {scroll.contentView.setBoundsOrigin(NSPoint(x:1,y:scroll.contentView.bounds.origin.y))}
        }
        scroll.contentView.setBoundsOrigin(NSPoint(x:10,y:240))
        check(reentrantNotifications < 8,"Reentrant layout notifications are bounded")
        NotificationCenter.default.removeObserver(observer)
        scroll.contentView.setBoundsOrigin(NSPoint(x:0,y:900))
        check(scroll.contentView.bounds.origin.y == 900,"Lower settings remain reachable")
        check(lock.hitTest(.zero)==nil,"Controls are not intercepted")
        lock.detach();check(scroll.horizontalScrollElasticity == .allowed && scroll.hasHorizontalScroller,"Teardown restores native settings")
        scroll.contentView.setBoundsOrigin(NSPoint(x:30,y:240));check(scroll.contentView.bounds.origin.x == 30,"Teardown removes bounds observer")

        // Actual production SwiftUI wrapper, with a deliberately oversized child.
        let host=NSHostingView(rootView:SettingsScrollView {
            VStack {ForEach(0..<30,id:\.self) {i in HStack {Text("Setting \(i)");Spacer();Button("Action") {}}.frame(height:44)}}
        }.padding(24).scaleEffect(0.924,anchor:.topLeading))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:320),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView=host;host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        func findScroll(_ view:NSView)->NSScrollView? {if let s=view as? NSScrollView {return s};for child in view.subviews {if let s=findScroll(child) {return s}};return nil}
        guard let native=findScroll(host) else {fatalError("FAIL: production wrapper contains native scroll view")}
        check(native.horizontalScrollElasticity == .none,"Production wrapper applies native horizontal lock")
        for delta in [-150.0,150.0] {
            native.contentView.setBoundsOrigin(NSPoint(x:delta,y:180))
            check(abs(native.contentView.bounds.origin.x) <= 0.5,"Production wrapper rejects sideways movement \(delta)")
            check(abs(native.contentView.bounds.origin.y - 180) < 1,"Production wrapper keeps vertical movement")
        }
        host.setFrameSize(NSSize(width:620,height:360));host.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        native.contentView.setBoundsOrigin(NSPoint(x:80,y:200))
        check(abs(native.contentView.bounds.origin.x) <= 0.5,"Horizontal lock survives viewport resizing")
        // Check real track placement and content clearance in both macOS modes.
        let edgeHost=NSHostingView(rootView:SettingsScrollView {
            VStack(spacing:0) {GutterProbe().frame(height:30);Color.clear.frame(height:1000)}
        }.padding(20))
        let edgeWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:320),styleMask:.borderless,backing:.buffered,defer:false)
        edgeWindow.contentView=edgeHost;edgeHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        guard let edgeScroll=findScroll(edgeHost) else {fatalError("Missing edge scroll")}
        func findProbe(_ view:NSView)->GutterProbeView? {if let probe=view as? GutterProbeView {return probe};for child in view.subviews {if let probe=findProbe(child) {return probe}};return nil}
        for style in [NSScroller.Style.overlay,.legacy] {
            edgeScroll.scrollerStyle=style;edgeScroll.hasVerticalScroller=true;edgeScroll.tile();edgeHost.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.1))
            let viewport=edgeScroll.convert(edgeScroll.bounds,to:edgeHost)
            check(abs(viewport.maxX-edgeHost.bounds.maxX)<2,"Scrollbar viewport reaches panel edge in mode \(style.rawValue)")
            guard let probe=findProbe(edgeHost) else {fatalError("Missing content probe")}
            let content=probe.convert(probe.bounds,to:edgeHost)
            check(viewport.maxX-content.maxX>=17,"Content stays clear of scrollbar in mode \(style.rawValue)")
        }
        print("RESULT: \(checks) native Settings scroll checks, zero failures")
    }
}

private final class GutterProbeView:NSView {}
private struct GutterProbe:NSViewRepresentable {
    func makeNSView(context:Context)->GutterProbeView {GutterProbeView()}
    func updateNSView(_ view:GutterProbeView,context:Context) {}
}
