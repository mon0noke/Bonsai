import Foundation

public enum CacheRemovalPolicy {
    /// Permanent mode is limited to generated cache leaves. Other data remains Trash-backed.
    public static func permits(_ item:ReviewItem,home:URL=FileManager.default.homeDirectoryForCurrentUser)->Bool {
        guard item.readOnlyReason==nil,item.absentBundleID==nil,item.risk != "High",item.category != "Trash" else {return false}
        let path=item.id,home=physicalURL(home).path
        if within(path,home+"/Library/Caches") {return true}
        let leaves:Set<String>=["Cache","Caches","Code Cache","GPUCache","DawnCache","DawnWebGPUCache","GraphiteDawnCache","CacheStorage","ShaderCache","CachedData","CachedExtensionVSIXs","CachedExtensions"]
        if within(path,home+"/Library/Application Support") || within(path,home+"/Library/Containers") {return leaves.contains(item.url.lastPathComponent)}
        return false
    }
}
public struct BonsaiShortcut:Codable,Equatable,Sendable {
    public let keyCode:UInt32
    /// Carbon modifiers, portable to RegisterEventHotKey (command=256, shift=512, option=2048, control=4096).
    public let modifiers:UInt32
    public let key:String
    public init(keyCode:UInt32,modifiers:UInt32,key:String) {self.keyCode=keyCode;self.modifiers=modifiers;self.key=String(key.prefix(12))}
    public var valid:Bool {keyCode<128 && keyCode != 53 && !key.isEmpty && modifiers & (256|2048|4096) != 0 && modifiers & ~(256|512|2048|4096)==0}
    public var title:String {(modifiers & 4096 != 0 ? "⌃":"")+(modifiers & 2048 != 0 ? "⌥":"")+(modifiers & 512 != 0 ? "⇧":"")+(modifiers & 256 != 0 ? "⌘":"")+key.uppercased()}
    public static func read(_ key:String,defaults:UserDefaults = .standard)->BonsaiShortcut? {guard let data=defaults.data(forKey:key),let value=try? JSONDecoder().decode(Self.self,from:data),value.valid else {return nil};return value}
    public static let openDefault=BonsaiShortcut(keyCode:11,modifiers:256|2048|4096,key:"B")
}
public enum MenuLifecyclePolicy {
    public static func keepRunning(menuVisible:Bool,keepMenu:Bool)->Bool {menuVisible && keepMenu}
    public static func hideDock(menuVisible:Bool,menuOnly:Bool,mainWindowVisible:Bool)->Bool {menuVisible && menuOnly && !mainWindowVisible}
}

/// Anchor a companion to the display containing the clicked status item.
public enum MenuPanelPlacement {
    public static func frame(anchor:CGRect,visible:CGRect,size:CGSize)->CGRect {
        let width=min(max(1,size.width),max(1,visible.width-16))
        let height=min(max(1,size.height),max(1,visible.height-16))
        let x=min(max(anchor.midX-width/2,visible.minX+8),visible.maxX-width-8)
        let y=max(visible.minY+8,min(anchor.minY-8-height,visible.maxY-height-8))
        return CGRect(x:x,y:y,width:width,height:height)
    }
}
