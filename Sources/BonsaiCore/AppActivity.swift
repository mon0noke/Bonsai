import Foundation
import Darwin

/// Activity is an estimate from app-owned data modification, never filesystem access.
/// Spotlight's launch date is kept separate because it does not establish subsequent use.
public struct AppActivity:Sendable {
    public let date:Date?;public let source:String
    public static func menuBarAgent(_ value:Any?)->Bool {
        if let value=value as? NSNumber {return value.boolValue}
        if let value=value as? String {return ["1","true","yes"].contains(value.lowercased())}
        return false
    }
    public static func inspect(bundleID:String,name:String,opened:Date?,home:URL=FileManager.default.homeDirectoryForCurrentUser,now:Date=Date())->AppActivity {
        var dates:[Date]=[]
        if bundleID.range(of:"^[A-Za-z0-9][A-Za-z0-9.-]+$",options:.regularExpression) != nil {
            var paths=["Library/Application Support/"+bundleID,"Library/Preferences/"+bundleID+".plist","Library/Saved Application State/"+bundleID+".savedState"]
            if name.count>=3,name.count<=100,!name.contains("/"),!name.contains(".."),!["Library","Application Support","Google","Adobe","Microsoft"].contains(name) {paths.append("Library/Application Support/"+name)}
            // Constant-size metadata reads; no contents, access timestamps or recursive scans.
            for path in paths {
                let url=home.appendingPathComponent(path)
                guard physicalURL(url.resolvingSymlinksInPath()).path==physicalURL(url).path,within(physicalURL(url).path,physicalURL(home).path),let identity=try? Identity.read(url),!identity.isSymlink,identity.owner==getuid(),
                      let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate,date<=now else {continue}
                dates.append(date)
            }
        }
        let active=dates.max(),opened=opened.flatMap {$0<=now ? $0:nil}
        if let active,opened==nil || active>=opened! {return AppActivity(date:active,source:"App data activity")}
        return AppActivity(date:opened,source:opened==nil ? "Unavailable":"Spotlight last used")
    }
    public static func old(_ date:Date,now:Date=Date(),calendar:Calendar = .current)->Bool {
        guard let boundary=calendar.date(byAdding:.month,value:-6,to:now) else {return false}
        return date<=boundary
    }
}
