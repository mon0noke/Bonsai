import AppKit
import Carbon
import BonsaiCore

@MainActor final class GlobalShortcuts:ObservableObject {
    static let shared=GlobalShortcuts()
    @Published var errors:[String:String]=[:]
    private var references:[EventHotKeyRef]=[]
    private var handler:EventHandlerRef?
    private var localMonitor:Any?
    var recording=false
    var actions:[String:()->Void]=[:]
    let keys=["openShortcut","awakeShortcut","screenShortcut"]
    init() {
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{_,event,context in
            guard let event,let context else {return OSStatus(eventNotHandledErr)}
            var identity=EventHotKeyID()
            let result=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&identity)
            guard result==noErr else {return result}
            let manager=Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {if !manager.recording && identity.id>0 && Int(identity.id)<=manager.keys.count {manager.actions[manager.keys[Int(identity.id)-1]]?()}}
            return noErr
        },1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func reload() {
        references.forEach {UnregisterEventHotKey($0)};references=[];var problems:[String:String]=[:]
        for (index,key) in keys.enumerated() {
            guard let shortcut=BonsaiShortcut.read(key) else {continue}
            var reference:EventHotKeyRef?
            let code=RegisterEventHotKey(shortcut.keyCode,shortcut.modifiers,EventHotKeyID(signature:0x424f4e53,id:UInt32(index+1)),GetApplicationEventTarget(),0,&reference)
            if code==noErr,let reference {references.append(reference)} else {problems[key]="This shortcut is already used or macOS refused it (\(code)). Choose another combination."}
        }
        if localMonitor==nil {
            localMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) {[weak self] event in
                guard let self,!self.recording else {return event}
                let flags=event.modifierFlags
                let modifiers:UInt32=(flags.contains(.command) ? 256:0)|(flags.contains(.shift) ? 512:0)|(flags.contains(.option) ? 2048:0)|(flags.contains(.control) ? 4096:0)
                for key in self.keys where self.errors[key]==nil {
                    if let shortcut=BonsaiShortcut.read(key),shortcut.keyCode==UInt32(event.keyCode),shortcut.modifiers==modifiers {self.actions[key]?();return nil}
                }
                return event
            }
        }
        errors=problems
    }
    func stop() {references.forEach {UnregisterEventHotKey($0)};references=[];if let localMonitor {NSEvent.removeMonitor(localMonitor)};localMonitor=nil}
}

import SwiftUI

/// A transparent event receiver lets the compact SwiftUI button own the visuals.
struct ShortcutCapture:NSViewRepresentable {
    let key:String
    @Binding var active:Bool
    @Binding var feedback:String
    var onChange:()->Void
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->NSView {NSView()}
    func updateNSView(_ view:NSView,context:Context) {
        context.coordinator.owner=self
        if active {context.coordinator.start()} else {context.coordinator.stop()}
    }
    static func dismantleNSView(_ view:NSView,coordinator:Coordinator) {coordinator.stop()}
    @MainActor final class Coordinator {
        var owner:ShortcutCapture?
        private var monitor:Any?
        private var resignObserver:NSObjectProtocol?
        func start() {
            guard monitor==nil else {return}
            GlobalShortcuts.shared.stop();GlobalShortcuts.shared.recording=true
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) {[weak self] event in
                guard let self,let owner=self.owner else {return event}
                if event.keyCode==53 {self.finish(changed:false);return nil}
                let flags=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let modifiers:UInt32=(flags.contains(.command) ? 256:0)|(flags.contains(.shift) ? 512:0)|(flags.contains(.option) ? 2048:0)|(flags.contains(.control) ? 4096:0)
                let shortcut=BonsaiShortcut(keyCode:UInt32(event.keyCode),modifiers:modifiers,key:event.charactersIgnoringModifiers ?? "")
                guard shortcut.valid else {owner.feedback="Use ⌘, ⌥ or ⌃";return nil}
                if GlobalShortcuts.shared.keys.contains(where:{$0 != owner.key && BonsaiShortcut.read($0).map {$0.keyCode==shortcut.keyCode && $0.modifiers==shortcut.modifiers} == true}) {owner.feedback="Already assigned";return nil}
                if let data=try? JSONEncoder().encode(shortcut) {UserDefaults.standard.set(data,forKey:owner.key)}
                self.finish(changed:true);return nil
            }
            resignObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) {[weak self] _ in
                Task {@MainActor in self?.finish(changed:false)}
            }
        }
        func stop() {
            guard monitor != nil else {return}
            if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil
            if let resignObserver {NotificationCenter.default.removeObserver(resignObserver)};resignObserver=nil
            GlobalShortcuts.shared.recording=false;GlobalShortcuts.shared.reload()
        }
        private func finish(changed:Bool) {
            let current=owner;stop();current?.active=false;current?.feedback=""
            if changed {current?.onChange()}
        }
    }
}
