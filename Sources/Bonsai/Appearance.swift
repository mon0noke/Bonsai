import SwiftUI
import AppKit

enum BonsaiAppearance: String, CaseIterable {
    case light, dark, system
    init(stored: String) { self = Self(rawValue: stored) ?? .light }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self { case .light: return .light; case .dark: return .dark; case .system: return nil }
    }
}

/// Named adaptive colors resolve in the receiving SwiftUI/AppKit appearance,
/// including sheets and menu extras, rather than a process-wide mutable theme.
enum Palette {
    static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("Bonsai." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    private static func color(_ name: String, _ light: (Double,Double,Double,Double), _ dark: (Double,Double,Double,Double)) -> Color {
        func ns(_ c: (Double,Double,Double,Double)) -> NSColor {
            NSColor(srgbRed:c.0,green:c.1,blue:c.2,alpha:c.3)
        }
        return Color(nsColor:adaptive(name,light:ns(light),dark:ns(dark)))
    }
    static let background=color("Background",(0.98,0.969,0.95,1),(0.12,0.145,0.135,1))
    static let card=color("Card",(0.965,0.973,0.946,1),(0.20,0.235,0.213,1))
    static let raised=color("Raised",(0.995,0.985,0.97,1),(0.19,0.225,0.20,1))
    static let accent=color("Accent",(0.93,0.68,0.67,1),(0.97,0.72,0.70,1))
    static let sage=color("Sage",(0.22,0.44,0.31,1),(0.64,0.80,0.63,1))
    static let muted=color("Muted",(0.30,0.35,0.31,1),(0.73,0.78,0.71,1))
    static let text=color("Text",(0.15,0.22,0.18,1),(0.96,0.96,0.90,1))
    static let line=color("Line",(0.13,0.22,0.23,0.12),(0.86,0.94,0.89,0.13))
    static let segment=color("Segment",(1,1,1,0.85),(0.38,0.47,0.44,0.75))
    static let ink=Color(red:0.13,green:0.22,blue:0.23)
    static let colors:[Color]=[accent,Color(red:0.49,green:0.72,blue:0.56),Color(red:0.46,green:0.67,blue:0.86),Color(red:0.84,green:0.69,blue:0.38),Color(red:0.65,green:0.60,blue:0.84)]
}

private struct AppearancePreference: ViewModifier {
    @AppStorage("appearance") private var stored=BonsaiAppearance.light.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme(BonsaiAppearance(stored:stored).scheme)
            .foregroundStyle(Palette.text).tint(Palette.sage)
    }
}
extension View {
    func bonsaiAppearance() -> some View { modifier(AppearancePreference()) }
}
