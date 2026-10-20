import AppKit
import SwiftUI

@main struct HoverChecks {
    @MainActor static func main() {
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ title:String) {checks+=1;guard value else {fatalError("FAIL: "+title)};print("PASS "+title)}
        let clip=NSClipView(frame:NSRect(x:0,y:0,width:600,height:410))
        let document=NSView(frame:NSRect(x:0,y:0,width:600,height:1000));clip.documentView=document
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:410),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView=clip
        for index in [7,8,9] {
            let row=StatusRowTrackingView(frame:NSRect(x:0,y:CGFloat(index)*44,width:600,height:44))
            document.addSubview(row);row.updateTrackingAreas()
            check(row.monitorsPointer,"Bottom row \(index+1) observes window mouse movement without waiting for telemetry")
            check(window.acceptsMouseMovedEvents,"Bottom row \(index+1) enables immediate window pointer delivery")
            let visible=row.bounds.intersection(row.visibleRect)
            check(!visible.isEmpty,"Bottom row \(index+1) has visible tracking geometry")
            check(row.containsPointer(NSPoint(x:300,y:visible.midY)),"Bottom row \(index+1) accepts pointer within its visible region")
            check(!row.containsPointer(NSPoint(x:601,y:visible.midY)),"Bottom row \(index+1) rejects points outside its width")
            row.enabled=false
            check(!row.containsPointer(NSPoint(x:300,y:visible.midY)),"Bottom row \(index+1) rejects background hover while an overlay is open")
            row.refreshPointer(publishingImmediately:true,location:NSPoint(x:300,y:visible.midY))
            check(!row.hovered,"Bottom row \(index+1) stays unhighlighted while disabled")
            row.enabled=true
            check(row.containsPointer(NSPoint(x:300,y:visible.midY)),"Bottom row \(index+1) accepts hover again after the overlay closes")
            check(row.hitTest(NSPoint(x:300,y:visible.midY))==nil,"Bottom row \(index+1) does not intercept buttons")
            check(row.trackingAreas.count==1,"Bottom row \(index+1) owns one tracking area")
            row.updateTrackingAreas();check(row.trackingAreas.count==1,"Bottom row \(index+1) replaces tracking area after recycling")
            check(row.trackingAreas[0].options.contains(.inVisibleRect),"Bottom row \(index+1) clips tracking to its scroll viewport")
            row.removeFromSuperview();check(!row.monitorsPointer,"Bottom row \(index+1) stops observing when removed")
            document.addSubview(row);check(row.monitorsPointer,"Bottom row \(index+1) restarts observing on reuse")
            row.stop();check(row.trackingAreas.isEmpty,"Bottom row \(index+1) removes tracking on teardown")
            check(!row.monitorsPointer,"Bottom row \(index+1) removes movement monitor on teardown")
            row.updateTrackingAreas();row.refreshPointer()
            check(row.trackingAreas.isEmpty && !row.hovered,"Bottom row \(index+1) cannot reactivate after teardown")
        }
        print("RESULT: \(checks) native row geometry/lifecycle checks, zero failures; no pointer events synthesized")
    }
}
