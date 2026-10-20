import SwiftUI
import BonsaiCore

struct AppActivityLabels:View {
    @EnvironmentObject private var model:AppModel
    let app:InstalledApp
    private var running:Bool {ApplicationActivity.isRunning([app.bundleID],among:model.runningAppIDs)}
    var body:some View {
        HStack(spacing:7) {
            if app.isMenuBarApp {Text("· Menu bar app").foregroundStyle(Palette.muted).help("Declared macOS agent app: usually lives in the menu bar and has no Dock icon. A visible menu-bar item is not guaranteed.")}
            if running {Text("· active now").foregroundStyle(Palette.sage)}
            else if let date=app.lastUsed,app.lastUsedSource != "Filesystem access" {
                Text("· "+(app.lastUsedSource=="Spotlight last used" ? "opened ":"active ")+date.formatted(.relative(presentation:.numeric)))
                    .foregroundStyle(AppActivity.old(date) ? Color(red:0.80,green:0.61,blue:0.25):Palette.muted)
                    .help(app.lastUsedSource=="Spotlight last used" ? "Last opened date reported by Spotlight. It does not establish ongoing activity." : "Estimated from modification of app support, preferences or saved state. Background writes can count as activity; scanning does not change these timestamps.")
            }
        }.font(.system(size:11,weight:.medium,design:.monospaced)).lineLimit(1)
    }
}
