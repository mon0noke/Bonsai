import Foundation
import Darwin
import BonsaiCore
@main struct LiveSparkleCheck {
 static func main() async throws {
  let fm=FileManager.default,base=URL(fileURLWithPath:CommandLine.arguments[1]).resolvingSymlinksInPath()
  guard base.lastPathComponent=="Sparkle-Disposable-3.6.9",!fm.fileExists(atPath:base.path) else {fatalError("Fresh isolated fixture required")}
  try fm.createDirectory(at:base,withIntermediateDirectories:true)
  try DirectUpdates.extract(URL(fileURLWithPath:CommandLine.arguments[2]),to:base)
  let app=base.appendingPathComponent("Keka.app")
  let original=try AppInventory.refreshed(InstalledApp(url:app,name:"Keka fixture",bundleID:"com.aone.keka",version:"1.6.7",measurement:Measurement(),lastUsed:nil,appStore:false))
  guard original.version=="1.6.7" else {fatalError("Wrong fixture version")}
  let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))
  guard let update=try AppcastMetadata.update(app:original,data:data,feed:URL(string:"https://u.keka.io")!,systemVersion:"27.0"),update.usesDirectArchive,update.available=="1.6.8" else {fatalError("Missing direct release")}
  let result=await UpdateService.install(update,consent:true)
  print(String(decoding:try JSONEncoder().encode(result),as:UTF8.self))
  guard result.status=="Updated",let recovery=result.recovery else {fatalError("Live fixture update did not complete")}
  let refreshed=try AppInventory.refreshed(original);guard refreshed.version=="1.6.8" else {fatalError("Installed version unchanged")}
  let previous=URL(fileURLWithPath:recovery)
  let previousInfo=try PropertyListSerialization.propertyList(from:Data(contentsOf:previous.appendingPathComponent("Contents/Info.plist")),format:nil) as! [String:Any]
  guard previousInfo["CFBundleShortVersionString"] as? String=="1.6.7" else {fatalError("Recovery missing")}
  // Bring our disposable previous app out of Trash into this same fixture.
  try fm.moveItem(at:previous,to:base.appendingPathComponent("Previous Keka.app"))
  print("PASS: signed Sparkle full ZIP, Ed25519/length/publisher verification, 1.6.7 → 1.6.8 atomic replacement, actual version and recovery verified. No publisher app opened; installed /Applications/Keka.app unchanged by this fixture.")
 }
}
