import Foundation
import AppKit
import BonsaiCore
@main struct CleanGuardChecks {
 @MainActor static func main() throws {
  var checks=0
  func check(_ condition:Bool,_ name:String) {checks+=1;print("\(condition ? "PASS" : "FAIL") \(name)");if !condition {exit(1)}}
  let defaults=UserDefaults.standard
  let saved=defaults.object(forKey:"exclusions")
  defer {if let saved {defaults.set(saved,forKey:"exclusions")} else {defaults.removeObject(forKey:"exclusions")}}
  let root=physicalURL(FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-guard-test-"+UUID().uuidString))
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  let file=root.appendingPathComponent("cache");try Data(repeating:1,count:4096).write(to:file)
  let item=try ReviewItem(url:file,title:"Fixture",category:"Application caches",explanation:"Disposable fixture",risk:"Low",measurement:FileScanner.measure(file))
  let model=AppModel(startServices:false);model.exclusions=[]
  let report=CleanReport(items:[item],issues:[],completeWithinCatalog:true)
  model.storeReport(report,mode:.caches);model.selected=[item.id]
  model.prepareReview([item],title:"Fixture")
  model.addExclusion(file)
  check(model.cleanItems.count==1,"Guard preserves the visible row")
  check(model.selected.isEmpty && model.reviewSelection.isEmpty,"Guard clears selection and pending review")
  check(model.isGuarded(item),"Guard state reflects exclusion")
  model.restoreRecommendedClean();check(model.selected.isEmpty,"Recommended cannot select a guarded path")
  model.prepareReview([item],title:"Fixture");check(model.reviewSelection.isEmpty,"New review cannot select a guarded path")
  model.storeReport(CleanReport(items:[],issues:[],completeWithinCatalog:true),mode:.caches)
  check(model.cleanItems.map(\.id)==[item.id],"Refresh preserves the guarded row")
  model.toggleGuard(item);check(!model.isGuarded(item) && model.selected.isEmpty,"Unguard does not silently reselect")
  model.restoreRecommendedClean();check(model.selected.contains(item.id),"Unguarded row becomes eligible")
  model.addExclusion(root);model.toggleGuard(item)
  check(model.exclusions.contains(root.path) && model.isGuarded(item),"Child unguard cannot remove an ancestor exclusion")
  check(try Data(contentsOf:file)==Data(repeating:1,count:4096),"Guard and unguard leave fixture contents unchanged")
  print("RESULT: \(checks) checks, 0 failures")
 }
}
