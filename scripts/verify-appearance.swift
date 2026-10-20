import AppKit
import SwiftUI

@main struct AppearanceChecks {
    @MainActor static func main() {
        var checks=0
        func check(_ value:Bool,_ note:String) { checks += 1; if !value { fatalError("FAIL: "+note) } }
        check(BonsaiAppearance(stored:"light").scheme == .light,"Light mapping")
        check(BonsaiAppearance(stored:"dark").scheme == .dark,"Dark mapping")
        check(BonsaiAppearance(stored:"system").scheme == nil,"System has no override")
        check(BonsaiAppearance(stored:"invalid").scheme == .light,"Unknown preference preserves daylight")
        check(Set(BonsaiAppearance.allCases.map(\.title)) == ["Light","Dark","System"],"Complete appearance choices")
        let dynamic=Palette.adaptive("Fixture",light:.black,dark:.white)
        func resolved(_ color:NSColor,_ name:NSAppearance.Name) -> NSColor {
            var result=NSColor.clear
            NSAppearance(named:name)!.performAsCurrentDrawingAppearance { result=color.usingColorSpace(.sRGB)! }
            return result
        }
        for name in [NSAppearance.Name.aqua,.accessibilityHighContrastAqua] {
            check(resolved(dynamic,name).redComponent < 0.01,"Light/high-contrast appearance resolves light")
        }
        for name in [NSAppearance.Name.darkAqua,.accessibilityHighContrastDarkAqua] {
            check(resolved(dynamic,name).redComponent > 0.99,"Dark/high-contrast appearance resolves dark")
        }
        func luminance(_ c:NSColor) -> Double {
            func linear(_ v:CGFloat)->Double { let d=Double(v);return d<=0.04045 ? d/12.92 : pow((d+0.055)/1.055,2.4) }
            return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
        }
        func contrast(_ a:NSColor,_ b:NSColor)->Double { let x=luminance(a),y=luminance(b);return (max(x,y)+0.05)/(min(x,y)+0.05) }
        for name in [NSAppearance.Name.aqua,.darkAqua] {
            let bg=resolved(NSColor(Palette.background),name)
            let text=resolved(NSColor(Palette.text),name),muted=resolved(NSColor(Palette.muted),name)
            check(contrast(text,bg)>=7,"Body contrast on base surface")
            check(contrast(muted,bg)>=4.5,"Secondary text contrast on base surface")
            check(contrast(text,resolved(NSColor(Palette.raised),name))>=7,"Body contrast on sheet/menu surface")
            check(contrast(muted,resolved(NSColor(Palette.raised),name))>=4.5,"Secondary text contrast on sheet/menu surface")
            print("\(name.rawValue): body \(String(format:"%.2f",contrast(text,bg))):1; secondary \(String(format:"%.2f",contrast(muted,bg))):1")
        }
        var requests:[Bool]=[]
        let cursor=LegacyHandCursor { requests.append($0) }
        let first=UUID(),second=UUID()
        cursor.update(id:first,active:true,enabled:true)
        check(cursor.owner==first && requests==[true],"Enabled hover requests a hand")
        cursor.update(id:first,active:true,enabled:true)
        check(requests==[true,true],"Continuous hover reapplies after host cursor updates")
        cursor.update(id:second,active:true,enabled:true)
        check(cursor.owner==second && requests.last==true,"Moving to another button transfers ownership")
        let before=requests.count
        cursor.release(id:first)
        check(cursor.owner==second && requests.count==before,"Late exit/removal cannot reset a newer hover")
        cursor.update(id:second,active:true,enabled:false)
        check(cursor.owner==nil && requests.last==false,"Disabling the hovered button restores its cursor")
        let cleared=requests.count
        cursor.release(id:second)
        check(requests.count==cleared,"Repeated teardown does not restore again")
        cursor.update(id:first,active:true,enabled:false)
        check(cursor.owner==nil && requests.count==cleared,"Disabled hover never requests a hand")
        cursor.update(id:first,active:true,enabled:true)
        cursor.update(id:first,active:false,enabled:true)
        check(cursor.owner==nil && requests.last==false,"Exit/removal/deactivation releases its owner")
        print("PASS: \(checks) appearance, contrast, hover ownership, disabled-state and cursor teardown checks; zero failures.")
        print("Native pointer entry/exit and system switching remain manual GUI checks; no window or global pointer is synthesized here.")
    }
}
