import AppKit
import SpriteKit

@main struct FrameRatePreview {
 @MainActor static func main() {
  let app=NSApplication.shared;app.setActivationPolicy(.regular)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:600),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  window.title="Bonsai Frame Rate Check";window.center()
  let view=SKView(frame:NSRect(x:0,y:0,width:600,height:600));view.preferredFramesPerSecond=60
  let image=NSImage(contentsOfFile:Bundle.main.resourceURL!.appendingPathComponent("PineBonsai.png").path)!
  let scene=LivingTreeScene(image:image,kind:.pine);scene.scanning=true
  var intervals:[Double]=[];var previous:Double?;var started:Double?
  let output=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("frame-rate-3.6.8.jsonl").path
  scene.frameObserver={time in
   if started==nil {started=time}
   if let previous,time-previous<0.2,time-started!>2 {intervals.append(time-previous)}
   previous=time
   if time-started!>12 {
    let sorted=intervals.sorted(),mean=intervals.reduce(0,+)/Double(max(1,intervals.count))
    let result:[String:Any]=["mode":scene.scanning ? "scan" : "idle","frames":intervals.count,"fps":1/mean,"p95_ms":sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count-1)*0.95)]*1000,"preferred":view.preferredFramesPerSecond]
    if let data=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys),let line=String(data:data,encoding:.utf8) {let old=(try? String(contentsOfFile:output,encoding:.utf8)) ?? "";try? (old+line+"\n").write(toFile:output,atomically:true,encoding:.utf8)}
    if scene.scanning {scene.scanning=false;started=time;previous=nil;intervals=[];window.title="Bonsai Frame Rate Check · idle"} else {scene.frameObserver=nil;window.title="Bonsai Frame Rate Check · finished"}
   }
  }
  view.presentScene(scene);view.isPaused=false;window.contentView=view
  window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);app.run()
 }
}
