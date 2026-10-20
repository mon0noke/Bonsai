import SwiftUI
import AppKit
import BonsaiCore
@main struct BonsaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    init() {
        BrandingMigration.run()
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        Window("Bonsai",id:"main") { RootView().environmentObject(model).compactInterface().onAppear { delegate.openMain={NSApp.setActivationPolicy(.regular);openWindow(id:"main");NSApp.windows.first {$0.title=="Bonsai"}?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)};delegate.model=model }.onReceive(NotificationCenter.default.publisher(for:.bonsaiOpenMain)) {_ in NSApp.setActivationPolicy(.regular);openWindow(id:"main");NSApp.windows.first {$0.title=="Bonsai"}?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)} }.defaultSize(width:1096,height:714).windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing:.newItem) {};CommandGroup(replacing:.appTermination) {Button("Quit Bonsai") {delegate.handleQuit()}.keyboardShortcut("q",modifiers:.command)}; CommandMenu("Care") { Button(model.page == .analyze ? "Refresh disk map" : "Scan current cleanup scope") {if model.page == .analyze {model.scanDisk(refresh:true)} else {model.scanCurrentClean()}}.handCursor().keyboardShortcut("r",modifiers:.command).disabled((model.page != .analyze && model.busy) || (model.page != .clean && model.page != .analyze)); Button("Cancel operation",action:model.cancel).handCursor().keyboardShortcut(".",modifiers:.command).disabled(!model.busy && !model.diskScanning); ForEach(Array(AppModel.Page.allCases.enumerated()),id:\.element) { index,page in Button("Show "+page.rawValue) { model.page=page }.handCursor().keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command) } } }

    }
}
