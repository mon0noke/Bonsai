import Foundation
import Darwin
import CBonsai

public struct LoginEntry:Identifiable,Sendable,Codable {
    public let id:String;public let name:String;public let identifier:String;public let owner:UInt32
    public let url:URL?;public let kind:String;public let enabled:Bool?;public let details:String
    public let section:String
    public init(id:String,name:String,identifier:String,owner:UInt32,url:URL?,kind:String,enabled:Bool?,details:String,section:String) {
        self.id=id;self.name=name;self.identifier=identifier;self.owner=owner;self.url=url;self.kind=kind;self.enabled=enabled;self.details=details;self.section=section
    }
    public var launchLabel:String? {
        guard kind=="Launch agent" || kind=="Launch daemon" else {return nil}
        let parts=identifier.split(separator:".",maxSplits:1)
        return parts.count==2 && UInt32(parts[0]) != nil ? String(parts[1]) : identifier.isEmpty ? nil : identifier
    }
}
public struct LoginInventorySnapshot:Codable,Sendable {
    public let entries:[LoginEntry];public let date:Date
    public init(entries:[LoginEntry],date:Date=Date()) {self.entries=entries;self.date=date}
    public func currentUser(_ uid:UInt32=getuid())->[LoginEntry] {entries.filter {$0.owner==uid}}
}
public struct LoginInventory:Sendable {public let entries:[LoginEntry];public let note:String}
public enum LoginItemInventory {
    /// sfltool's diagnostic format is not a stable API: reject unknown records
    /// instead of treating an unparsed or unavailable state as disabled.
    public static func parse(_ output:String,uid:UInt32=getuid())->LoginInventory {
        var currentUID:UInt32?;var fields:[String:String]=[:];var raw:[[String:String]]=[]
        func commit() {if currentUID==uid,fields["UUID"] != nil {raw.append(fields)};fields=[:]}
        for line in output.split(separator:"\n",omittingEmptySubsequences:false) {
            let value=line.trimmingCharacters(in:.whitespaces)
            if value.contains("Records for UID") {
                commit();let tail=value.components(separatedBy:"Records for UID").last ?? ""
                currentUID=tail.split(whereSeparator:{$0.isWhitespace || $0==":"}).first.flatMap {UInt32($0)};continue
            }
            if value.hasPrefix("#") {commit();continue}
            if value.hasPrefix("UUID:"),fields["UUID"] != nil {commit()}
            guard let colon=value.firstIndex(of:":") else {continue}
            let key=String(value[..<colon]);let data=value[value.index(after:colon)...].trimmingCharacters(in:.whitespaces)
            if ["UUID","Name","Identifier","Bundle Identifier","Parent Identifier","URL","Type","Disposition"].contains(key) {fields[key]=data}
        }
        commit()
        let parents=Dictionary(raw.compactMap {r -> (String,[String:String])? in guard let id=r["Identifier"] else {return nil};return (id,r)},uniquingKeysWith:{a,_ in a})
        func words(_ r:[String:String])->Set<String> {Set((r["Disposition"] ?? "").lowercased().split(whereSeparator:{!$0.isLetter}).map(String.init))}
        func allowed(_ r:[String:String])->Bool? {let w=words(r);return w.contains("disallowed") ? false : w.contains("allowed") ? true : nil}
        func active(_ r:[String:String])->Bool? {let w=words(r);if w.contains("disabled") || w.contains("disallowed") {return false};return w.contains("enabled") && w.contains("allowed") ? true : nil}
        func localURL(_ r:[String:String])->URL? {
            guard let path=r["URL"],path != "(null)" else {return nil}
            if path.hasPrefix("/") {return URL(fileURLWithPath:path)}
            if let url=URL(string:path),url.isFileURL,url.host.map({$0.isEmpty || $0=="localhost"}) != false {return url}
            if path.hasPrefix("Contents/"),let id=r["Parent Identifier"],let parent=parents[id],let base=localParentURL(parent) {
                let candidate=base.appendingPathComponent(path).standardizedFileURL
                return within(candidate.path,base.path) ? candidate : nil
            }
            return nil
        }
        func localParentURL(_ r:[String:String])->URL? {guard let path=r["URL"],path.hasPrefix("/") else {return nil};return URL(fileURLWithPath:path)}
        var records:[LoginEntry]=[]
        for r in raw {
            guard let type=r["Type"],let uuid=r["UUID"],let name=r["Name"],!uuid.isEmpty,name != "(null)",!name.isEmpty else {continue}
            let lower=type.lowercased();let app=lower.hasPrefix("app ") || lower=="app"
            if app {
                let isLogin=words(r).contains("enabled")
                let children=r["Identifier"].map {id in raw.filter {$0["Parent Identifier"]==id && ($0["Type"]?.lowercased().contains("login item")==true || $0["Type"]?.lowercased().contains("background tasks")==true)}} ?? []
                // App 'disabled' means Open at Login is off. It does not mean
                // background permission is denied. That state comes from allowed.
                let identifier=r["Bundle Identifier"] ?? r["Identifier"] ?? ""
                let kind=isLogin ? "App · opens at login" : children.isEmpty ? "App · background permission" : "App · background helpers"
                let detailLines=children.compactMap {child -> String? in guard let childName=child["Name"] else {return nil};return childName+": "+(child["Disposition"] ?? "State unavailable")}
                let details=([r["Disposition"] ?? "State unavailable"]+detailLines).joined(separator:"\n")
                let section=isLogin ? "Login items" : "Allow in the background"
                records.append(LoginEntry(id:"btm:"+uuid,name:name,identifier:identifier,owner:uid,url:localURL(r),kind:kind,enabled:isLogin ? active(r) : allowed(r),details:details,section:section))
                continue
            }
            if lower.contains("login item") || lower.contains("background tasks") {
                if let id=r["Parent Identifier"],parents[id]?["Type"]?.hasPrefix("app")==true {continue}
            } else if !lower.contains("agent") && !lower.contains("daemon") {continue}
            records.append(LoginEntry(id:"btm:"+uuid,name:name,identifier:r["Identifier"] ?? "",owner:uid,url:localURL(r),kind:lower.contains("agent") ? "Launch agent" : lower.contains("daemon") ? "Launch daemon" : "Login helper",enabled:active(r),details:r["Disposition"] ?? "State unavailable",section:"Background services"))
        }
        let unique=Dictionary(records.map {($0.id,$0)},uniquingKeysWith: {a,_ in a}).values.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
        return LoginInventory(entries:Array(unique),note:records.isEmpty ? "No supported records for the current user were returned. This is not proof that no login items exist; use System Settings to inspect the complete list." : "Current-user registrations read from macOS. Login switches show registration state; background switches show permission. Neither proves a process is running. Managed apps use System Settings for changes.")
    }

    public static func readWithAuthorization() async throws -> LoginInventory {
        let worker=Task.detached(priority:.utility) { () throws -> LoginInventory in
            var output:UnsafeMutablePointer<CChar>?
            let code=bonsai_read_login_inventory(&output)
            guard code==0,let output else {throw BonsaiError.unavailable(code == -60006 ? "Login-item access was cancelled. You can retry or open System Settings." : "macOS could not read login items (\(code)). Retry or use System Settings.")}
            defer {bonsai_free_inventory(output)}
            try Task.checkCancellation();return parse(String(cString:output))
        }
        return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    }
}
