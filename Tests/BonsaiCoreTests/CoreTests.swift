import XCTest
import Foundation
import CryptoKit
import Darwin
@testable import BonsaiCore

final class CoreTests: XCTestCase {
 var root: URL!
 override func setUpWithError() throws { root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("bonsai-tests-"+UUID().uuidString).resolvingSymlinksInPath(); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true) }
 override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at:root) } }
 func file(_ path: String, _ count: Int = 8192) throws -> URL { let u=root.appendingPathComponent(path); try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true); try Data(repeating:42,count:count).write(to:u); return u }
 func item(_ url: URL, ids: [String] = []) throws -> ReviewItem { try ReviewItem(url:url,title:url.lastPathComponent,category:"Test",explanation:"Disposable fixture",runningIDs:ids,measurement:FileScanner.measure(url)) }

 func testHealthScoreUsesMeasuredPressureAndReportsInputs() {
  var sample=TelemetrySnapshot();sample.memoryTotal=16;sample.diskTotal=100;sample.diskFree=40;sample.pressure="Normal";sample.thermal="Nominal"
  XCTAssertEqual(HealthAssessment.evaluate(sample,now:sample.date).title,"100 Good")
  sample.pressure="Warning";let warning=HealthAssessment.evaluate(sample,now:sample.date)
  XCTAssertEqual(warning.title,"84 Good");XCTAssertTrue(warning.explanation.contains("Memory pressure −16"))
  sample.thermal="Fair";sample.diskFree=10
  XCTAssertEqual(HealthAssessment.evaluate(sample,now:sample.date).score,61)
  sample.pressure="Critical";sample.thermal="Critical";sample.diskFree=0
  XCTAssertEqual(HealthAssessment.evaluate(sample,now:sample.date).title,"0 Needs care")
 }
 func testHealthScoreNeverInventsMissingOrStaleReadings() {
  var sample=TelemetrySnapshot();XCTAssertNil(HealthAssessment.evaluate(sample,now:sample.date).score)
  sample.memoryTotal=16;sample.diskTotal=100;sample.diskFree=25;sample.pressure="Normal";sample.thermal="Nominal"
  XCTAssertNil(HealthAssessment.evaluate(sample,now:sample.date.addingTimeInterval(11)).score)
  XCTAssertNil(HealthAssessment.evaluate(sample,now:sample.date.addingTimeInterval(-3)).score)
  sample.diskFree=101;XCTAssertNil(HealthAssessment.evaluate(sample,now:sample.date).score)
  XCTAssertTrue(HealthAssessment.inputs.contains("CPU, GPU and battery charge do not affect"))
 }
 func testTemperatureUnitConversionHandlesMissingSensors() {
  XCTAssertEqual(TemperatureUnit.celsius.format(celsius:20),"20°C")
  XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius:20),"68°F")
  XCTAssertEqual(TemperatureUnit.celsius.format(celsius:nil),"Unavailable")
  XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius:.nan),"Unavailable")
 }
 func testShortcutPersistenceAndBoundaryValidation() throws {
  let name="bonsai-shortcut-fixture-"+UUID().uuidString,defaults=UserDefaults(suiteName:name)!
  defer {defaults.removePersistentDomain(forName:name)}
  let shortcut=BonsaiShortcut.openDefault;XCTAssertTrue(shortcut.valid);XCTAssertEqual(shortcut.title,"⌃⌥⌘B")
  defaults.set(try JSONEncoder().encode(shortcut),forKey:"openShortcut");XCTAssertEqual(BonsaiShortcut.read("openShortcut",defaults:defaults),shortcut)
  defaults.set(Data("broken".utf8),forKey:"openShortcut");XCTAssertNil(BonsaiShortcut.read("openShortcut",defaults:defaults))
  XCTAssertFalse(BonsaiShortcut(keyCode:53,modifiers:256,key:"Escape").valid)
  XCTAssertFalse(BonsaiShortcut(keyCode:1,modifiers:512,key:"S").valid)
  XCTAssertFalse(BonsaiShortcut(keyCode:200,modifiers:256,key:"S").valid)
  XCTAssertFalse(BonsaiShortcut(keyCode:1,modifiers:256|8192,key:"S").valid)
 }
 func testMenuLifecycleCannotHideOnlyRemainingAccess() {
  XCTAssertTrue(MenuLifecyclePolicy.keepRunning(menuVisible:true,keepMenu:true))
  XCTAssertFalse(MenuLifecyclePolicy.keepRunning(menuVisible:false,keepMenu:true))
  XCTAssertTrue(MenuLifecyclePolicy.hideDock(menuVisible:true,menuOnly:true,mainWindowVisible:false))
  XCTAssertFalse(MenuLifecyclePolicy.hideDock(menuVisible:false,menuOnly:true,mainWindowVisible:false))
  XCTAssertFalse(MenuLifecyclePolicy.hideDock(menuVisible:true,menuOnly:true,mainWindowVisible:true))
 }
 func testPermanentCachePreviewAndExplicitConfirmation() async throws {
  let cache=try file("Library/Caches/app.fixture/cache.bin"),policy=PathPolicy(roots:[root])
  let reviewed=try item(cache)
  let preview=await TrashService.perform([reviewed],policy:policy,runningIDs:{[]},dryRun:true,permanentCaches:true,cacheHome:root)
  XCTAssertEqual(preview.first?.status,"Preview");XCTAssertTrue(FileManager.default.fileExists(atPath:cache.path))
  let refused=await TrashService.perform([reviewed],policy:policy,runningIDs:{[]},permanentCaches:true,cacheHome:root)
  XCTAssertEqual(refused.first?.status,"Skipped");XCTAssertTrue(FileManager.default.fileExists(atPath:cache.path))
  let removed=await TrashService.perform([reviewed],policy:policy,runningIDs:{[]},permanentCaches:true,confirmed:true,cacheHome:root)
  XCTAssertEqual(removed.first?.status,"Deleted");XCTAssertNil(removed.first?.recovery);XCTAssertFalse(FileManager.default.fileExists(atPath:cache.path))
 }
 func testPermanentCacheModeKeepsPersonalDataAndChangedFiles() async throws {
  let personal=try file("Library/Application Support/Fixture/projects/data.bin")
  XCTAssertFalse(CacheRemovalPolicy.permits(try item(personal),home:root))
  let policy=PathPolicy(roots:[root]),destination=root.appendingPathComponent("fixture-trash.bin")
  let retained=await TrashService.perform([try item(personal)],policy:policy,runningIDs:{[]},permanentCaches:true,confirmed:true,cacheHome:root,mover:{url in try FileManager.default.moveItem(at:url,to:destination);return destination})
  XCTAssertEqual(retained.first?.status,"Trashed");XCTAssertTrue(FileManager.default.fileExists(atPath:destination.path))
  let cache=try file("Library/Caches/changed.bin"),reviewed=try item(cache)
  try Data(repeating:12,count:90).write(to:cache)
  let changed=await TrashService.perform([reviewed],policy:policy,runningIDs:{[]},permanentCaches:true,confirmed:true,cacheHome:root)
  XCTAssertEqual(changed.first?.status,"Skipped");XCTAssertTrue(FileManager.default.fileExists(atPath:cache.path))
  let running=try item(cache,ids:["app.fixture.running"])
  let stopped=await TrashService.perform([running],policy:policy,runningIDs:{["app.fixture.running"]},permanentCaches:true,confirmed:true,cacheHome:root)
  XCTAssertEqual(stopped.first?.status,"Skipped")
 }
 func testAwakeBehaviorChangesReleaseOldAssertions() throws {
  let power=PowerAssertion()
  for behavior in AwakeBehavior.allCases {try power.set(true,behavior:behavior);XCTAssertTrue(power.active)}
  try power.set(false);XCTAssertFalse(power.active)
 }
 func testActivityUsesModificationNotAccessAndKeepsOpenedDistinct() throws {
  let now=Date(timeIntervalSince1970:1_800_000_000),past=now.addingTimeInterval(-86400*200)
  let preference=try file("Library/Preferences/app.fixture.activity.plist")
  try FileManager.default.setAttributes([.modificationDate:past],ofItemAtPath:preference.path)
  let active=AppActivity.inspect(bundleID:"app.fixture.activity",name:"Fixture",opened:nil,home:root,now:now)
  XCTAssertEqual(active.source,"App data activity");XCTAssertEqual(active.date!.timeIntervalSince1970,past.timeIntervalSince1970,accuracy:1)
  let opened=AppActivity.inspect(bundleID:"app.fixture.activity",name:"Fixture",opened:now.addingTimeInterval(-100),home:root,now:now)
  XCTAssertEqual(opened.source,"Spotlight last used");XCTAssertEqual(opened.date,now.addingTimeInterval(-100))
  let empty=AppActivity.inspect(bundleID:"../outside",name:"../outside",opened:now.addingTimeInterval(10),home:root,now:now)
  XCTAssertNil(empty.date);XCTAssertEqual(empty.source,"Unavailable")
 }
 func testActivityRejectsLinksAndSixMonthBoundary() throws {
  let outside=try file("outside/preferences.plist"),link=root.appendingPathComponent("Library/Preferences/app.fixture.activity.plist")
  try FileManager.default.createDirectory(at:link.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
  XCTAssertNil(AppActivity.inspect(bundleID:"app.fixture.activity",name:"Fixture",opened:nil,home:root).date)
  var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
  let now=calendar.date(from:DateComponents(year:2026,month:10,day:8))!,boundary=calendar.date(byAdding:.month,value:-6,to:now)!
  XCTAssertTrue(AppActivity.old(boundary,now:now,calendar:calendar));XCTAssertFalse(AppActivity.old(boundary.addingTimeInterval(1),now:now,calendar:calendar))
  XCTAssertTrue(AppActivity.menuBarAgent(true));XCTAssertTrue(AppActivity.menuBarAgent("YES"));XCTAssertFalse(AppActivity.menuBarAgent("no"));XCTAssertFalse(AppActivity.menuBarAgent(nil))
 }
 func testInventoryRetainsMenuBarClassificationAfterSizing() throws {
  let app=try fixtureApp(extra:["LSUIElement":true]);let inventory=try AppInventory.scan(roots:[app.url],measureSizes:false)
  XCTAssertTrue(inventory[0].isMenuBarApp);XCTAssertTrue(try AppSizePipeline.measure(inventory[0]).isMenuBarApp)
  XCTAssertTrue(try AppInventory.refreshed(inventory[0]).isMenuBarApp)
 }
 func testDoctorReportsActualIssuesAndUnavailableInputs() {
  var sample=TelemetrySnapshot();sample.date=Date();sample.cpu=90;sample.pressure="Warning";sample.thermal="Serious";sample.diskTotal=100;sample.diskFree=9
  XCTAssertEqual(DoctorReport.detected(sample,now:sample.date).count,4)
  sample.cpu=5;sample.pressure="Normal";sample.thermal="Nominal";sample.diskFree=20
  XCTAssertTrue(DoctorReport.detected(sample,now:sample.date).isEmpty)
  XCTAssertEqual(DoctorReport.detected(sample,now:sample.date.addingTimeInterval(20)).count,1)
  let access=FileAccess.check(home:root,read:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(EACCES))})
  let report=DoctorReport.make(snapshot:sample,access:access,environment:[],configuration:[],runtime:[],now:sample.date)
  XCTAssertTrue(report.text.contains("Access needed"));XCTAssertTrue(report.text.contains("No supported source enabled"));XCTAssertFalse(report.text.contains("Granted"))
 }
 func testScreenSessionAlwaysHasBoundedAutomaticExit() {
  for duration in [60,120,300] {XCTAssertEqual(ScreenSession.duration(duration),duration)}
  for invalid in [0,-1,Int.max,3600] {XCTAssertEqual(ScreenSession.duration(invalid),60)}
 }

 func testFastDiskWalkMatchesAllocationAndDoesNotFollowSymlinks() throws {
  let a=try file("tree/a",12345);let tree=a.deletingLastPathComponent()
  _=try file("tree/sub/b",4567);_=try file("tree/sub/zero",0)
  let outside=try file("outside/keep",1_000_000)
  try FileManager.default.createSymbolicLink(at:tree.appendingPathComponent("external"),withDestinationURL:outside)
  try FileManager.default.linkItem(at:a,to:tree.appendingPathComponent("sub/hardlink"))
  let reference=try FileScanner.measure(tree,diskAccounting:true),fast=try DiskTreeScanner.measure(tree,limits:ScanLimits())
  XCTAssertTrue(fast.complete);XCTAssertEqual(fast.allocated,reference.allocated);XCTAssertEqual(fast.logical,reference.logical);XCTAssertEqual(fast.files,reference.files);XCTAssertEqual(fast.manifest.count,1)
  XCTAssertFalse(fast.hasExternalLinks);XCTAssertTrue(FileManager.default.fileExists(atPath:outside.path))
  let single=try DiskTreeScanner.measure(a,limits:ScanLimits());XCTAssertTrue(single.hasExternalLinks)
 }
 func testFastDiskWalkLimitsPermissionAndCancellation() async throws {
  for i in 0..<40 {_=try file("tree/sub/file\(i)")}
  let tree=root.appendingPathComponent("tree")
  let limited=try DiskTreeScanner.measure(tree,limits:ScanLimits(nodes:3,seconds:10));XCTAssertFalse(limited.complete);XCTAssertEqual(limited.scannedNodes,3)
  let inaccessible=root.appendingPathComponent("tree/sub");try FileManager.default.setAttributes([.posixPermissions:0o000],ofItemAtPath:inaccessible.path)
  defer {try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:inaccessible.path)}
  let denied=try DiskTreeScanner.measure(tree,limits:ScanLimits());XCTAssertFalse(denied.complete);XCTAssertTrue(denied.accessDeniedPaths?.contains(physicalURL(inaccessible).path)==true)
  let task=Task {try await Task.sleep(nanoseconds:1_000_000_000);return try DiskTreeScanner.measure(tree,limits:ScanLimits())};task.cancel()
  do {_=try await task.value;XCTFail("Cancelled disk scan ran")} catch is CancellationError {} catch {XCTFail(error.localizedDescription)}
 }
 func testGPUValidationPreservesZeroAndRejectsInvalidSnapshots() {
  XCTAssertEqual(GPUTelemetry.parse(["Device Utilization %":0],cores:8).utilization,0)
  XCTAssertEqual(GPUTelemetry.parse(["Device Utilization %":24],cores:8).cores,8)
  for invalid in [true,"24",-1,101,Double.nan,Double.infinity] as [Any] {XCTAssertNil(GPUTelemetry.parse(["Device Utilization %":invalid]).utilization)}
  XCTAssertNil(GPUTelemetry.parse([:]).utilization);XCTAssertNil(GPUTelemetry.parse([:],cores:0).cores)
 }

 func testExpandedCleanFindsCatalogCategoriesAndPreservesPersonalData() throws {
  let paths=["Library/Caches/Steam/data","Library/Application Support/Steam/appcache/data","Library/Application Support/Steam/logs/log", ".cache/opencode/data", ".cache/uv/data", ".npm/_logs/log", "Library/Caches/Homebrew/downloads/package", "Library/Caches/com.apple.bird/data", "Library/Caches/CloudKit/com.apple.bird/account/Assets/data", "Library/Containers/com.example.app/Data/Library/Caches/cache/data", "Library/Application Support/Firefox/Profiles/fixture/cache2/data", ".Trash/disposable/data"]
  for path in paths {_=try file(path)}
  let personal=["Library/CloudStorage/Dropbox/keep", "Library/Containers/com.example.app/Data/Documents/keep", "Library/Containers/com.example.app/Data/Library/Preferences/settings", "Library/Application Support/Firefox/Profiles/fixture/cookies.sqlite", ".cache/CloudKit/not-an-asset"]
  for path in personal {_=try file(path)}
  let system=root.appendingPathComponent("fixture-system");_=try file("fixture-system/Library/Caches/example/data");_=try file("fixture-system/private/var/log/system.log")
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"),systemRoot:system)
  let categories=Set(report.items.map {CleanFlow.category($0.category)})
  XCTAssertTrue(Set(["Misc","AI Tools","Developer Tools","Cloud Storage","App Caches","Browsers","System Caches","Trash"]).isSubset(of:categories))
  for path in personal {let url=root.appendingPathComponent(path);XCTAssertFalse(report.items.contains {within(url.path,$0.id)});XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))}
  let recommended=CleanFlow.recommended(report.items,runningIDs:[])
  XCTAssertTrue(report.items.filter {$0.category=="System Caches" || $0.category=="Trash"}.allSatisfy {!recommended.contains($0.id)})
  XCTAssertTrue(report.items.contains {$0.id.hasSuffix(".cache/opencode") && recommended.contains($0.id)})
  XCTAssertEqual(report.items.filter {$0.id.contains("CloudKit")}.map(\.title),["iCloud Drive cache assets"])
 }
 func testExpandedCleanExclusionsAndOverlappingRules() throws {
  let steam=try file("Library/Caches/Steam/data"),appcache=try file("Library/Application Support/Steam/appcache/data")
  _=try file("Library/Caches/Homebrew/downloads/file")
  let report=try CleanCatalog.scan(home:root,exclusions:[steam.deletingLastPathComponent().path],temporaryRoot:root.appendingPathComponent("temporary"))
  XCTAssertFalse(report.items.contains {$0.id==steam.deletingLastPathComponent().path})
  XCTAssertTrue(report.items.contains {$0.id==physicalURL(appcache.deletingLastPathComponent()).path})
  for a in report.items {XCTAssertFalse(report.items.contains {$0.id != a.id && within(a.id,$0.id)})}
 }
 func testContainerCacheScopeIsNarrowAndPreservesExclusions() throws {
  let cache=try file("Library/Containers/com.example.app/Data/Library/Caches/generated/data").deletingLastPathComponent()
  let documents=try file("Library/Containers/com.example.app/Data/Documents/keep")
  let containers=root.appendingPathComponent("Library/Containers")
  let base=PathPolicy(roots:[root],protected:[containers,root.appendingPathComponent(".Trash")])
  XCTAssertThrowsError(try base.validate(cache))
  let scoped=try ContainerCacheScope.policy(for:item(cache),base:base,home:root)
  XCTAssertNoThrow(try scoped.validate(cache));XCTAssertThrowsError(try scoped.validate(documents))
  XCTAssertThrowsError(try ContainerCacheScope.policy(for:item(documents),base:base,home:root))
  let excluded=PathPolicy(roots:[root],protected:[containers,cache])
  XCTAssertThrowsError(try ContainerCacheScope.policy(for:item(cache),base:excluded,home:root).validate(cache))
  let allExcluded=PathPolicy(roots:[root],protected:[containers,containers])
  XCTAssertThrowsError(try ContainerCacheScope.policy(for:item(cache),base:allExcluded,home:root).validate(cache))
 }
 func testContainerCacheScopeRejectsSymlinkAndChangedOwner() throws {
  let cache=try file("Library/Containers/com.example.app/Data/Library/Caches/generated/data").deletingLastPathComponent()
  let reviewed=try item(cache),container=root.appendingPathComponent("Library/Containers/com.example.app")
  let base=PathPolicy(roots:[root],protected:[root.appendingPathComponent("Library/Containers")])
  let moved=root.appendingPathComponent("moved-container");try FileManager.default.moveItem(at:container,to:moved)
  try FileManager.default.createSymbolicLink(at:container,withDestinationURL:moved)
  XCTAssertThrowsError(try ContainerCacheScope.policy(for:reviewed,base:base,home:root))
  try FileManager.default.removeItem(at:container);try FileManager.default.moveItem(at:moved,to:container)
  XCTAssertThrowsError(try ContainerCacheScope.policy(for:reviewed,base:PathPolicy(roots:[root],uid:getuid()+1),home:root))
 }
 func testExpandedDiscoveryDoesNotFollowContainerOrBrowserLinks() throws {
  let outside=try file("outside/Data/Library/Caches/cache/data").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  _=try file("outside/cache2/data")
  let containers=root.appendingPathComponent("Library/Containers");try FileManager.default.createDirectory(at:containers,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(at:containers.appendingPathComponent("com.example.link"),withDestinationURL:outside)
  let profiles=root.appendingPathComponent("Library/Application Support/Firefox/Profiles");try FileManager.default.createDirectory(at:profiles,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(at:profiles.appendingPathComponent("linked"),withDestinationURL:outside)
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"))
  XCTAssertFalse(report.items.contains {$0.id.contains("com.example.link") || $0.id.contains("/linked/")})
  XCTAssertTrue(FileManager.default.fileExists(atPath:outside.path))
 }
 func testHomebrewOldVersionsAreComparedWithActiveOptLink() throws {
  _=try file("fixture-system/opt/homebrew/Cellar/python/3.9/data")
  _=try file("fixture-system/opt/homebrew/Cellar/python/3.10/data")
  _=try file("fixture-system/opt/homebrew/Cellar/python/3.11/data")
  let opt=root.appendingPathComponent("fixture-system/opt/homebrew/opt");try FileManager.default.createDirectory(at:opt,withIntermediateDirectories:true)
  try FileManager.default.createSymbolicLink(atPath:opt.appendingPathComponent("python").path,withDestinationPath:"../Cellar/python/3.10")
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"),systemRoot:root.appendingPathComponent("fixture-system"))
  let versions=report.items.filter {$0.title.hasPrefix("Homebrew old version")}
  XCTAssertEqual(versions.count,1);XCTAssertTrue(versions.first?.id.hasSuffix("python/3.9")==true)
  XCTAssertNotNil(versions.first?.readOnlyReason);XCTAssertTrue(CleanFlow.recommended(versions,runningIDs:[]).isEmpty)
 }
 func testOrphanServiceDiscoveryRequiresMissingAbsoluteExecutable() throws {
  let existing=try file("fixture-system/bin/keep")
  for (name,program) in [("missing","/missing/executable"),("present","/bin/keep"),("relative","bin/keep")] {
   let plist=try file("fixture-system/Library/LaunchDaemons/"+name+".plist")
   try PropertyListSerialization.data(fromPropertyList:["Label":"com.example."+name,"ProgramArguments":[program]],format:.xml,options:0).write(to:plist)
  }
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"),systemRoot:root.appendingPathComponent("fixture-system"))
  let orphans=report.items.filter {$0.title.hasPrefix("Possible orphaned service")}
  XCTAssertEqual(orphans.count,1);XCTAssertTrue(orphans.first?.id.hasSuffix("missing.plist")==true);XCTAssertNotNil(orphans.first?.readOnlyReason)
  XCTAssertTrue(FileManager.default.fileExists(atPath:existing.path))
 }
 func testReadOnlyAndTrashNeverUseOrdinaryCleanup() async throws {
  let f=try file(".Trash/keep"),m=try FileScanner.measure(f)
  let trash=try ReviewItem(url:f,title:"Trash",category:"Trash",explanation:"Fixture",measurement:m)
  let readOnly=try ReviewItem(url:f,title:"Inventory",category:"System Caches",explanation:"Fixture",measurement:m,readOnlyReason:"System managed")
  let outcomes=await TrashService.perform([trash,readOnly],policy:PathPolicy(roots:[root]),runningIDs:{[]},mover:{_ in XCTFail("Unsupported item reached mover");return nil})
  XCTAssertEqual(outcomes.map(\.status),["Skipped","Skipped"]);XCTAssertTrue(FileManager.default.fileExists(atPath:f.path))
  XCTAssertTrue(CleanFlow.recommended([trash,readOnly],runningIDs:[]).isEmpty)
 }
 func testTrashPurgeRequiresConfirmationAndPreviewDoesNotDelete() async throws {
  let f=try file(".Trash/keep");let reviewed=try ReviewItem(url:f,title:"Keep",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(f))
  let trash=f.deletingLastPathComponent()
  let refused=await TrashPurge.perform([reviewed],root:trash)
  XCTAssertEqual(refused.first?.status,"Skipped")
  let preview=await TrashPurge.perform([reviewed],root:trash,dryRun:true,remover:{_ in XCTFail("Preview deleted data")})
  XCTAssertEqual(preview.first?.status,"Preview");XCTAssertTrue(FileManager.default.fileExists(atPath:f.path))
 }
 func testTrashPurgeDeletesOnlyReviewedDisposableItems() async throws {
  let chosen=try file(".Trash/chosen/data").deletingLastPathComponent(),keep=try file(".Trash/keep")
  let reviewed=try ReviewItem(url:chosen,title:"Chosen",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(chosen))
  let outcomes=await TrashPurge.perform([reviewed],root:chosen.deletingLastPathComponent(),confirmed:true)
  XCTAssertEqual(outcomes.first?.status,"Deleted");XCTAssertNil(outcomes.first?.recovery)
  XCTAssertFalse(FileManager.default.fileExists(atPath:chosen.path));XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path))
 }
 func testTrashPurgeRejectsChangedItemsWrongRootsAndExclusions() async throws {
  let f=try file(".Trash/keep");let reviewed=try ReviewItem(url:f,title:"Keep",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(f))
  let trash=f.deletingLastPathComponent()
  let wrong=await TrashPurge.perform([reviewed],root:root,confirmed:true);XCTAssertEqual(wrong.first?.status,"Skipped")
  let excluded=await TrashPurge.perform([reviewed],root:trash,exclusions:[f.path],confirmed:true);XCTAssertEqual(excluded.first?.status,"Skipped")
  try Data(repeating:1,count:123).write(to:f)
  let stale=await TrashPurge.perform([reviewed],root:trash,confirmed:true);XCTAssertEqual(stale.first?.status,"Skipped");XCTAssertTrue(FileManager.default.fileExists(atPath:f.path))
 }
 func testTrashPurgeCancellationAndSymlinkContainment() async throws {
  let outside=try file("outside/keep"),dir=try file(".Trash/chosen/data").deletingLastPathComponent()
  try FileManager.default.createSymbolicLink(at:dir.appendingPathComponent("escape"),withDestinationURL:outside)
  let reviewed=try ReviewItem(url:dir,title:"Keep",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(dir))
  let unsafe=await TrashPurge.perform([reviewed],root:dir.deletingLastPathComponent(),confirmed:true);XCTAssertEqual(unsafe.first?.status,"Skipped")
  let trash=dir.deletingLastPathComponent(),ordinary=try file(".Trash/ordinary")
  let valid=try ReviewItem(url:ordinary,title:"Cancelled",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(ordinary))
  let worker=Task.detached {try await Task.sleep(nanoseconds:50_000_000);return await TrashPurge.perform([valid],root:trash,confirmed:true)};worker.cancel()
  do {_=try await worker.value;XCTFail("Cancellation lost")} catch is CancellationError {} catch {XCTFail("Unexpected cancellation error")}
  XCTAssertTrue(FileManager.default.fileExists(atPath:outside.path));XCTAssertTrue(FileManager.default.fileExists(atPath:ordinary.path))
 }

 func testEdgeUpdaterKeepsNewestAndInstalledPayloads() throws {
  let relative="Library/Application Support/Microsoft/EdgeUpdater/apps/msedge-stable/"
  for version in ["141.0.9.1","141.0.10.1","142.0.1.1"] {_=try file(relative+version+"/payload")}
  _=try file(relative+"metadata/keep")
  let fallback=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"))
  XCTAssertEqual(fallback.items.filter {$0.title.hasPrefix("Edge updater old")}.count,2)
  XCTAssertFalse(fallback.items.contains {$0.id.hasSuffix("142.0.1.1") || $0.id.hasSuffix("metadata")})
  let metadata=try file("Applications/Microsoft Edge.app/Contents/Info.plist")
  try PropertyListSerialization.data(fromPropertyList:["CFBundleShortVersionString":"141.0.10.1"],format:.xml,options:0).write(to:metadata)
  let installed=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"))
  let old=installed.items.filter {$0.title.hasPrefix("Edge updater old")}
  XCTAssertEqual(old.count,1);XCTAssertTrue(old.first?.id.hasSuffix("141.0.9.1")==true);XCTAssertTrue(CleanFlow.recommended(old,runningIDs:[]).isEmpty)
 }
 func testTrashPurgePartialFailureHasAnHonestOutcome() async throws {
  let selected=try file(".Trash/selected/first"),keep=try file(".Trash/selected/second"),folder=selected.deletingLastPathComponent()
  let reviewed=try ReviewItem(url:folder,title:"Partial",category:"Trash",explanation:"Fixture",measurement:FileScanner.measure(folder))
  let outcomes=await TrashPurge.perform([reviewed],root:folder.deletingLastPathComponent(),confirmed:true,remover:{url in try FileManager.default.removeItem(at:url.appendingPathComponent("first"));throw BonsaiError.unavailable("Fixture failure")})
  XCTAssertEqual(outcomes.first?.status,"Partial failure");XCTAssertTrue(outcomes.first?.detail.contains("Some contents may have been removed")==true)
  XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path));XCTAssertFalse(FileManager.default.fileExists(atPath:selected.path))
 }
 func testTrashPurgeCancellationAfterOneDisposableItem() async throws {
  let first=try file(".Trash/first"),second=try file(".Trash/second")
  let items=try [first,second].map {try ReviewItem(url:$0,title:$0.lastPathComponent,category:"Trash",explanation:"Fixture",measurement:FileScanner.measure($0))}
  let trash=first.deletingLastPathComponent()
  let worker=Task.detached {await TrashPurge.perform(items,root:trash,confirmed:true,remover:{url in try FileManager.default.removeItem(at:url);withUnsafeCurrentTask {$0?.cancel()}})}
  let outcomes=await worker.value
  XCTAssertEqual(outcomes.map(\.status),["Deleted","Cancelled"]);XCTAssertTrue(FileManager.default.fileExists(atPath:second.path));XCTAssertFalse(FileManager.default.fileExists(atPath:first.path))
 }

 func testExpandedRiskDefaultsKeepModelsAndArchivesUnselected() {
  for path in [".ollama/models",".lmstudio/models",".cache/huggingface/hub","Library/Developer/Xcode/Archives","Library/Developer/Xcode/iOS DeviceSupport"] {XCTAssertEqual(CacheRules.selectionRisk(category:"AI tools",relative:path),"High")}
  for path in [".cache/opencode",".cache/uv","Library/Application Support/Cursor/Cache"] {XCTAssertEqual(CacheRules.selectionRisk(category:"AI tools",relative:path),"Review")}
  XCTAssertEqual(CacheRules.selectionRisk(category:"Browsers",relative:"Chrome/Service Worker/CacheStorage"),"High")
 }
 func testExpandedPermissionFailureRetainsOtherCategories() throws {
  _=try file("Library/Caches/Steam/data")
  let denied=root.appendingPathComponent("Library/Containers");try FileManager.default.createDirectory(at:denied,withIntermediateDirectories:true)
  XCTAssertEqual(chmod(denied.path,0),0);defer {_=chmod(denied.path,0o700)}
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"))
  XCTAssertFalse(report.completeWithinCatalog);XCTAssertTrue(report.accessDeniedPaths.contains(denied.path));XCTAssertTrue(report.items.contains {$0.category=="Misc"})
 }

 func testCleanScanActivityCountsHardlinksOnceAndReportsPaths() throws {
  let first=try file("Library/Caches/one/data",65536)
  let second=root.appendingPathComponent("Library/Caches/two/data")
  try FileManager.default.createDirectory(at:second.deletingLastPathComponent(),withIntermediateDirectories:true)
  try FileManager.default.linkItem(at:first,to:second)
  let temp=root.appendingPathComponent("temporary");try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  let probe=CleanActivityFixture()
  let report=try CleanCatalog.scan(home:root,temporaryRoot:temp,activity:{probe.append($0)})
  XCTAssertEqual(report.items.count,2)
  let samples=probe.samples;XCTAssertFalse(samples.isEmpty)
  XCTAssertEqual(samples.last?.allocated,try FileScanner.measure(first).allocated)
  XCTAssertTrue(samples.allSatisfy {within(physicalURL(URL(fileURLWithPath:$0.location)).path,physicalURL(root).path)})
  XCTAssertTrue(zip(samples,samples.dropFirst()).allSatisfy {$0.allocated<=$1.allocated})
  let excluded=CleanActivityFixture()
  _=try CleanCatalog.scan(home:root,exclusions:[first.deletingLastPathComponent().path,second.deletingLastPathComponent().path],temporaryRoot:temp,activity:{excluded.append($0)})
  XCTAssertTrue(excluded.samples.isEmpty)
 }
 func testCleanScanActivityCancellationStopsDiscovery() async throws {
  _=try file("Library/Caches/fixture/data")
  let probe=CleanActivityFixture(),home=root!
  let task=Task.detached {try Task.checkCancellation();return try CleanCatalog.scan(home:home,activity:{probe.append($0)})}
  task.cancel()
  do {_=try await task.value;XCTFail("Cancelled scan completed")} catch is CancellationError {} catch {XCTFail("Unexpected cancellation error")}
 }
 func testDedicatedScanLayoutFitsCompactAndLargeWindows() {
  for height in [0.0,100,400,480,620,1000,Double.nan,Double.infinity] {
   for width in [0.0,100,320,980,2000,Double.nan,Double.infinity] {
    let size=BonsaiActivityMotion.scanPortraitSize(height:height,width:width)
    XCTAssertTrue(size.isFinite && size>=0 && size<=360)
    if height>=160 && height.isFinite && width>=48 && width.isFinite {XCTAssertTrue(size+160<=height && size+48<=width)}
   }
  }
  XCTAssertEqual(BonsaiActivityMotion.scanPortraitSize(height:700,width:1000),360)
 }
 func testBotanicalActivityMotionIsBoundedAndPeriodic() {
  XCTAssertEqual(BonsaiActivityMotion.phase(elapsed:-1),0)
  XCTAssertEqual(BonsaiActivityMotion.phase(elapsed:.nan),0)
  XCTAssertEqual(BonsaiActivityMotion.phase(elapsed:.infinity),0)
  XCTAssertEqual(BonsaiActivityMotion.phase(elapsed:2,period:0),0)
  XCTAssertEqual(BonsaiActivityMotion.phase(elapsed:2,period:.nan),0)
  for time in [0.0,0.1,1.2,4.99,5,500,1e12] {
   for index in [-1,0,1,7,8,Int.max] {
    let leaf=BonsaiActivityMotion.leaf(index:index,elapsed:time)
    XCTAssertTrue(leaf.x>=0.09 && leaf.x<=0.91)
    XCTAssertTrue(leaf.y>=0.13 && leaf.y<=0.55)
    XCTAssertTrue(leaf.angle.isFinite && leaf.opacity>=0.34 && leaf.opacity<=0.66)
   }
  }
  let a=BonsaiActivityMotion.leaf(index:2,elapsed:1.25),b=BonsaiActivityMotion.leaf(index:2,elapsed:6.25)
  XCTAssertEqual(a.x,b.x,accuracy:0.00001);XCTAssertEqual(a.y,b.y,accuracy:0.00001)
  let end=BonsaiActivityMotion.leaf(index:0,elapsed:4.999999),start=BonsaiActivityMotion.leaf(index:0,elapsed:5)
  XCTAssertEqual(end.x,start.x,accuracy:0.00001);XCTAssertEqual(end.y,start.y,accuracy:0.00001)
 }
 func testActivityLayoutReservesChromeAndFitsShortWindows() {
  XCTAssertTrue(BonsaiActivityMotion.titlebarInset*0.924>28)
  for height in [0.0,180,420,480,550,620,800,2000,Double.nan,Double.infinity] {
   for checklist in [true,false] {
    let art=BonsaiActivityMotion.portraitSize(height:height,checklist:checklist)
    XCTAssertTrue(art.isFinite && art>=100 && art<=300)
   }
   XCTAssertTrue((1...4).contains(BonsaiActivityMotion.checklistRows(height:height)))
  }
  XCTAssertTrue(BonsaiActivityMotion.portraitSize(height:500,checklist:true)<BonsaiActivityMotion.portraitSize(height:500,checklist:false))
  XCTAssertEqual(BonsaiActivityMotion.checklistRows(height:420),1)
  XCTAssertEqual(BonsaiActivityMotion.checklistRows(height:550),2)
  XCTAssertEqual(BonsaiActivityMotion.checklistRows(height:800),4)
 }
 func testBonsaiGrowthAndBoundedPruning() {
  XCTAssertEqual(BonsaiGrowth.level(bytes:0),0)
  XCTAssertEqual(BonsaiGrowth.level(bytes:10_000_000),0)
  XCTAssertEqual(BonsaiGrowth.level(bytes:1_000_000_000),0.5)
  XCTAssertEqual(BonsaiGrowth.level(bytes:100_000_000_000),1)
  XCTAssertEqual(BonsaiGrowth.level(bytes:UInt64.max),1)
  XCTAssertTrue(BonsaiGrowth.level(bytes:500_000_000)<BonsaiGrowth.level(bytes:5_000_000_000))
  XCTAssertEqual(BonsaiGrowth.pruningProgress(elapsed:-2),0)
  XCTAssertEqual(BonsaiGrowth.pruningProgress(elapsed:0.8),0.5)
  XCTAssertEqual(BonsaiGrowth.pruningProgress(elapsed:10),1)
  XCTAssertEqual(BonsaiGrowth.pruningProgress(elapsed:.nan),0)
  XCTAssertEqual(BonsaiGrowth.pruningProgress(elapsed:.infinity),1)
 }
 func testRealisticBonsaiCanopyKeepsRootsAndPruningBounded() {
  for growth in [0.0,0.5,1.0] {
   XCTAssertEqual(BonsaiGrowth.canopyScale(topY:0.8,growth:growth,pruning:0),1)
   XCTAssertTrue(BonsaiGrowth.canopyScale(topY:0.1,growth:growth,pruning:0)>1)
   var previous=1.3
   for step in 0...16 {
    let value=BonsaiGrowth.canopyScale(topY:0.1,growth:growth,pruning:Double(step)/16)
    XCTAssertTrue(value>=1 && value<=1.25)
    XCTAssertTrue(value<=previous);previous=value
   }
   XCTAssertEqual(BonsaiGrowth.canopyScale(topY:0.1,growth:growth,pruning:1),1)
  }
  XCTAssertTrue(BonsaiGrowth.canopyScale(topY:0.1,growth:1,pruning:0)>BonsaiGrowth.canopyScale(topY:0.1,growth:0,pruning:0))
  XCTAssertEqual(BonsaiGrowth.canopyScale(topY:.nan,growth:1,pruning:0),1)
 }
 func testDiskTrashPartialFolderMovesWithoutTraversingLinks() throws {
  let target=try file("outside/keep.txt"),folder=try file("chosen/file.txt").deletingLastPathComponent()
  try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("link"),withDestinationURL:target)
  let measurement=try FileScanner.measure(folder);XCTAssertFalse(measurement.complete)
  let request=try DiskTrashRequest(DiskEntry(url:folder,directory:true,measurement:measurement))
  let destination=root.appendingPathComponent("recoverable")
  let outcome=DiskTrash.perform(request,policy:PathPolicy(roots:[root]),mover:{url in try FileManager.default.moveItem(at:url,to:destination);return destination})
  XCTAssertEqual(outcome.status,"Trashed");XCTAssertEqual(outcome.recovery,destination.path)
  XCTAssertTrue(FileManager.default.fileExists(atPath:target.path));XCTAssertFalse(FileManager.default.fileExists(atPath:folder.path))
  try FileManager.default.moveItem(at:destination,to:folder)
  XCTAssertTrue(FileManager.default.fileExists(atPath:folder.appendingPathComponent("file.txt").path))
 }
 func testDiskTrashRejectsChangedIdentityProtectedAndRunningItems() throws {
  let file=try file("app/file.txt"),entry=DiskEntry(url:file,directory:false,measurement:try FileScanner.measure(file))
  let request=try DiskTrashRequest(entry),policy=PathPolicy(roots:[root])
  let running=DiskTrash.perform(request,policy:policy,runningApplications:{[file.appendingPathComponent("nested.app")]},mover:{_ in XCTFail("Running item moved");return nil})
  XCTAssertEqual(running.status,"Skipped")
  let protected=DiskTrash.perform(request,policy:PathPolicy(roots:[root],protected:[file]),mover:{_ in XCTFail("Protected item moved");return nil})
  XCTAssertEqual(protected.status,"Skipped")
  try Data(repeating:1,count:100).write(to:file)
  let changed=DiskTrash.perform(request,policy:policy,mover:{_ in XCTFail("Changed item moved");return nil})
  XCTAssertEqual(changed.status,"Skipped");XCTAssertTrue(changed.detail.contains("changed"))
 }
 func testDiskTrashMissingRootSymlinkOwnershipAndMoverFailure() throws {
  let file=try file("file.txt"),policy=PathPolicy(roots:[root])
  XCTAssertThrowsError(try DiskTrashRequest(DiskEntry(url:file,directory:false,measurement:Measurement())))
  let link=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
  let linked=try DiskTrashRequest(DiskEntry(url:link,directory:false,measurement:FileScanner.measure(link)))
  XCTAssertEqual(DiskTrash.perform(linked,policy:policy,mover:{_ in XCTFail("Link moved");return nil}).status,"Skipped")
  let request=try DiskTrashRequest(DiskEntry(url:file,directory:false,measurement:FileScanner.measure(file)))
  XCTAssertEqual(DiskTrash.perform(request,policy:PathPolicy(roots:[root],uid:getuid()+1),mover:{_ in XCTFail("Other owner moved");return nil}).status,"Skipped")
  let failed=DiskTrash.perform(request,policy:policy,mover:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(EACCES))})
  XCTAssertEqual(failed.status,"Skipped");XCTAssertNil(failed.recovery);XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
 }
 func testDiskTrashCancellationAndParentReplacement() async throws {
  let file=try file("folder/file.txt"),folder=file.deletingLastPathComponent(),policy=PathPolicy(roots:[root])
  let request=try DiskTrashRequest(DiskEntry(url:file,directory:false,measurement:FileScanner.measure(file)))
  let cancelled=Task {withUnsafeCurrentTask {$0?.cancel()};return DiskTrash.perform(request,policy:policy,mover:{_ in XCTFail("Cancelled item moved");return nil})}
  let cancelResult=await cancelled.value;XCTAssertEqual(cancelResult.status,"Cancelled")
  let old=root.appendingPathComponent("old");try FileManager.default.moveItem(at:folder,to:old)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  try FileManager.default.moveItem(at:old.appendingPathComponent("file.txt"),to:file)
  let result=DiskTrash.perform(request,policy:policy,mover:{_ in XCTFail("Replaced parent moved");return nil})
  XCTAssertEqual(result.status,"Skipped");XCTAssertTrue(result.detail.contains("folder changed"))
 }
 func testProcessInspectorRejectsRelaunchedGroup() {
  let old=ProcessSample(pid:30,uid:getuid(),start:10,startMicro:1,name:"Demo",memory:100,cpu:2,cpuNS:1,executable:"/Applications/Demo.app/Contents/MacOS/Demo")
  let new=ProcessSample(pid:30,uid:getuid(),start:20,startMicro:1,name:"Demo",memory:200,cpu:3,cpuNS:2,executable:old.executable)
  let initial=ProcessGrouping.groups([old])[0];let relaunched=ProcessGrouping.groups([new])
  XCTAssertEqual(initial.id,relaunched[0].id)
  XCTAssertNil(ProcessInspection.liveGroup(initial,in:relaunched))
  XCTAssertNotNil(ProcessInspection.liveGroup(initial,in:[initial]))
  XCTAssertNil(ProcessInspection.liveGroup(initial,in:[]))
 }
 func testInspectorParentTrailBoundsCyclesAndNewerParents() {
  func p(_ id:Int32,_ parent:Int32,_ start:UInt64)->ProcessSample {ProcessSample(pid:id,uid:501,start:start,startMicro:0,name:"P",memory:0,cpu:0,cpuNS:0,parentPID:parent)}
  let one=p(1,0,1),two=p(2,1,2),three=p(3,2,3)
  XCTAssertEqual(ProcessInspection.parents(of:three,in:[one,two,three]).map(\.pid),[1,2])
  XCTAssertTrue(ProcessInspection.parents(of:three,in:[p(2,1,4)]).isEmpty)
  let cycleA=p(5,6,5),cycleB=p(6,5,5)
  XCTAssertEqual(ProcessInspection.parents(of:cycleA,in:[cycleA,cycleB]).map(\.pid),[6])
  let many=(1...30).map {p(Int32($0),Int32($0-1),UInt64($0))}
  XCTAssertEqual(ProcessInspection.parents(of:many.last!,in:many).count,16)
 }
 func testNativeProcessDetailsAndStaleIdentity() async {
  let snapshot=await TelemetryCollector().sample()
  guard let own=snapshot.processes.first(where:{$0.pid==getpid()}) else {XCTFail("Own process missing");return}
  let reader=ProcessDetailCollector();let detail=await reader.read(own)
  XCTAssertNotNil(detail);XCTAssertEqual(detail?.identity,own.id)
  XCTAssertNotNil(detail?.threads);XCTAssertNotNil(detail?.openFiles);XCTAssertNotNil(detail?.bytesRead)
  let stale=ProcessSample(pid:own.pid,uid:own.uid,start:own.start,startMicro:own.startMicro+1,name:own.name,memory:0,cpu:0,cpuNS:0)
  let rejected=await reader.read(stale);XCTAssertNil(rejected)
  XCTAssertThrowsError(try TelemetryCollector.terminate(stale,force:true))
 }
 func testOpenDescriptorCountIsNotTableCapacity() async throws {
  let url=try file("descriptor-count");let fd=open(url.path,O_RDONLY);XCTAssertTrue(fd>=0);defer {if fd>=0 {close(fd)}}
  let snapshot=await TelemetryCollector().sample();guard let own=snapshot.processes.first(where:{$0.pid==getpid()}) else {XCTFail("Own process missing");return}
  let reader=ProcessDetailCollector();let before=await reader.read(own)
  let high=fcntl(fd,F_DUPFD_CLOEXEC,128);XCTAssertTrue(high>=128);defer {if high>=0 {close(high)}}
  let after=await reader.read(own)
  XCTAssertNotNil(before?.openFiles);XCTAssertNotNil(after?.openFiles)
  XCTAssertEqual(after?.openFiles,(before?.openFiles).map {$0+1})
 }
 func testProcessForceQuitOnlyDisposableFixture() async throws {
  let fixture=Process();fixture.executableURL=URL(fileURLWithPath:"/bin/sleep");fixture.arguments=["20"];try fixture.run()
  defer {if fixture.isRunning {fixture.terminate()}}
  let snapshot=await TelemetryCollector().sample()
  guard let p=snapshot.processes.first(where:{$0.pid==fixture.processIdentifier}) else {XCTFail("Fixture missing");return}
  let stale=ProcessSample(pid:p.pid,uid:p.uid,start:p.start+1,startMicro:p.startMicro,name:p.name,memory:0,cpu:0,cpuNS:0)
  XCTAssertThrowsError(try TelemetryCollector.terminate(stale,force:true));XCTAssertTrue(fixture.isRunning)
  try TelemetryCollector.terminate(p,force:true)
  for _ in 0..<50 {if !fixture.isRunning {break};try await Task.sleep(nanoseconds:20_000_000)}
  XCTAssertFalse(fixture.isRunning);XCTAssertEqual(fixture.terminationReason,.uncaughtSignal);XCTAssertEqual(fixture.terminationStatus,SIGKILL)
  XCTAssertThrowsError(try TelemetryCollector.terminate(p,force:true))
 }
 func testActivityCountsExcludePreviewsAndFailures() {
  let entries=[AuditEntry(operation:"Uninstall applications",outcomes:[ItemOutcome(title:"Demo",path:"/Applications/Demo.app",status:"Trashed",detail:"fixture"),ItemOutcome(title:"data",path:"~/Library/Caches/Demo",status:"Trashed",detail:"fixture"),ItemOutcome(title:"Fail",path:"/Applications/Fail.app",status:"Skipped",detail:"fixture")]),AuditEntry(operation:"Maintenance",outcomes:[ItemOutcome(title:"A",path:"",status:"Completed",detail:"fixture"),ItemOutcome(title:"B",path:"",status:"Failed",detail:"fixture")]),AuditEntry(operation:"Cleanup preview",outcomes:[ItemOutcome(title:"Preview",path:"/Applications/Preview.app",status:"Preview",detail:"fixture")])]
  let counts=ActivityCounts(entries:entries);XCTAssertEqual(counts.trashMoves,2);XCTAssertEqual(counts.applications,1);XCTAssertEqual(counts.maintenanceTasks,1)
 }
 func testMaintenancePlanAndCapabilities() {
  let plan=MaintenanceRunner.plan(selected:["power","quicklook","not-a-task","disk"])
  XCTAssertEqual(plan.map(\.id),["quicklook","disk","power"])
  XCTAssertTrue(MaintenanceRunner.plan(selected:[]).isEmpty)
  XCTAssertEqual(MaintenanceTask.catalog.filter(\.recommended).count,19)
  XCTAssertFalse(MaintenanceTask.catalog.first {$0.id=="disk"}!.recommended)
  XCTAssertTrue(MaintenanceTask.catalog.first {$0.id=="power"}!.readOnly)
  XCTAssertFalse(MaintenanceTask.catalog.first {$0.id=="quicklook"}!.readOnly)
  XCTAssertEqual(Set(MaintenanceTask.catalog.map(\.group)),["Finder previews","Application databases","System checks","Finder preferences","Disk health","Additional checks"])
 }
 func testMaintenanceBatchDedupAndFailureContinuation() async {
  let tasks=MaintenanceTask.catalog;let trace=MaintenanceFixtureTrace()
  let outcomes=await MaintenanceRunner.run([tasks[0],tasks[0],tasks[1]],progress:{i,t,_ in await trace.add("progress:\(i):"+t.id)},execute:{ t in
   await trace.add("run:"+t.id);return ItemOutcome(title:t.title,path:t.preview,status:t.id=="quicklook" ? "Failed" : "Completed",detail:"Fixture only")
  })
  XCTAssertEqual(outcomes.count,2);XCTAssertEqual(outcomes.map(\.status),["Failed","Completed"])
  let values=await trace.values();XCTAssertEqual(values,["progress:0:quicklook","run:quicklook","progress:1:generators","run:generators"])
 }
 func testDirectOptimizePlanExcludesOptionalTasks() async {
  let plan=MaintenanceRunner.quickPlan
  let expected=MaintenanceTask.catalog.filter { ["cache_refresh","sqlite_vacuum","launch_agents_cleanup","spotlight_index_optimize","periodic_maintenance","spotlight","power","saved_state_cleanup","fix_broken_configs","login_items_audit","audit_system_maintenance","audit_network_optimization","audit_network_stack_optimize","audit_disk_permissions_repair","audit_spotlight_orphan_rules_cleanup","shared_file_list_repair","audit_quarantine_cleanup","audit_notification_cleanup","audit_coreduet_cleanup"].contains($0.id) && $0.available }
  XCTAssertEqual(plan.map(\.id),expected.map(\.id))
  XCTAssertFalse(plan.contains {$0.id=="disk"})
  XCTAssertTrue(plan.allSatisfy {$0.available && $0.recommended})
  let trace=MaintenanceFixtureTrace()
  let result=await MaintenanceRunner.run(plan,execute:{ task in
   await trace.add(task.id)
   return ItemOutcome(title:task.title,path:task.preview,status:"Completed",detail:"Direct-action fixture; no commands run")
  })
  let calls=await trace.values()
  XCTAssertEqual(calls,expected.map(\.id))
  XCTAssertEqual(result.count,expected.count)
  XCTAssertTrue(result.allSatisfy {$0.status=="Completed"})
 }
 func testMaintenanceCancelAtProgressNeverStartsCommands() async {
  let trace=MaintenanceFixtureTrace();let tasks=Array(MaintenanceTask.catalog.prefix(2))
  let worker=Task {await MaintenanceRunner.run(tasks,progress:{_,_,_ in withUnsafeCurrentTask {$0?.cancel()}},execute:{t in await trace.add(t.id);return ItemOutcome(title:t.title,path:t.preview,status:"Completed",detail:"Unexpected")})}
  let result=await worker.value;let calls=await trace.values()
  XCTAssertTrue(calls.isEmpty);XCTAssertEqual(result.count,2);XCTAssertTrue(result.allSatisfy {$0.status=="Skipped"})
 }
 func testMaintenanceCancelledWorkerCannotStartNextTask() async {
  let trace=MaintenanceFixtureTrace();let tasks=Array(MaintenanceTask.catalog.prefix(3))
  let worker=Task {await MaintenanceRunner.run(tasks,execute:{t in
   await trace.add(t.id);withUnsafeCurrentTask {$0?.cancel()};return ItemOutcome(title:t.title,path:t.preview,status:"Completed",detail:"Fixture ignores cancellation")
  })}
  let result=await worker.value;let calls=await trace.values()
  XCTAssertEqual(calls,["quicklook"]);XCTAssertEqual(result.map(\.status),["Completed","Skipped","Skipped"])
 }
 func testMaintenanceOperationFailureDoesNotVerify() async {
  let trace=MaintenanceFixtureTrace();let task=MaintenanceTask.catalog[0]
  let outcome=await task.perform(using:{_,args,_ in await trace.add(args.joined(separator:" "));return CommandResult(status:1,output:"fixture failure")})
  let calls=await trace.values();XCTAssertEqual(calls,["-r cache"]);XCTAssertEqual(outcome.status,"Failed");XCTAssertTrue(outcome.detail.contains("fixture failure"))
 }
 func testMaintenanceVerificationTimeoutAndCancellation() async {
  let task=MaintenanceTask.catalog[0]
  let timeout=await task.perform(using:{_,args,_ in CommandResult(status:args.first=="-r" ? 0 : 15,output:"fixture",timedOut:args.first != "-r")})
  XCTAssertEqual(timeout.status,"Verification failed");XCTAssertTrue(timeout.detail.contains("Timed out."))
  let cancelled=await task.perform(using:{_,args,_ in CommandResult(status:0,output:"fixture",cancelled:args.first != "-r")})
  XCTAssertEqual(cancelled.status,"Cancelled");XCTAssertTrue(cancelled.detail.contains("post-check was cancelled"))
 }
 func testMaintenanceCancelledAfterOperationKeepsOutput() async {
  let trace=MaintenanceFixtureTrace();let task=MaintenanceTask.catalog[0]
  let worker=Task {await task.perform(using:{_,args,_ in await trace.add(args.joined(separator:" "));withUnsafeCurrentTask {$0?.cancel()};return CommandResult(status:0,output:"Operation already finished")})}
  let value=await worker.value;let calls=await trace.values()
  XCTAssertEqual(calls,["-r cache"]);XCTAssertEqual(value.status,"Cancelled");XCTAssertTrue(value.detail.contains("Operation already finished"))
 }
 func testMaintenanceSummarySeparatesChecksAndChanges() {
  let tasks=MaintenanceTask.catalog
  let values=zip(tasks,["Completed","Verification failed","Completed","Skipped","Cancelled"]).map {t,status in ItemOutcome(title:t.title,path:t.preview,status:status,detail:"Fixture")}
  let summary=MaintenanceSummary(tasks:tasks,outcomes:values)
  XCTAssertEqual(summary.refreshed,1);XCTAssertEqual(summary.checked,1);XCTAssertEqual(summary.otherCompleted,0)
  XCTAssertEqual(summary.attention,2);XCTAssertEqual(summary.skipped,1);XCTAssertEqual(summary.completed,2)
  XCTAssertEqual(summary.label,"1 refreshed · 1 checked · 2 need attention · 1 skipped")
  XCTAssertEqual(summary.headline(cancelled:false),"A little more care needed");XCTAssertEqual(summary.headline(cancelled:true),"Maintenance stopped")
 }
 func testMaintenanceSummaryEmptyAndUnclassifiedCompletion() {
  let empty=MaintenanceSummary(tasks:[],outcomes:[])
  XCTAssertEqual(empty.completed,0);XCTAssertEqual(empty.label,"No tasks ran")
  let unknown=MaintenanceSummary(tasks:[],outcomes:[ItemOutcome(title:"Unknown",path:"fixture",status:"Completed",detail:"")])
  XCTAssertEqual(unknown.refreshed,0);XCTAssertEqual(unknown.label,"1 completed");XCTAssertEqual(unknown.headline(cancelled:false),"Maintenance complete")
 }
 func testPathBoundariesAndRoot() throws { let f=try file("owned"); let p=PathPolicy(roots:[root]); XCTAssertNoThrow(try p.validate(f)); XCTAssertThrowsError(try p.validate(root)); XCTAssertThrowsError(try p.validate(URL(fileURLWithPath:root.path+"-sibling"))) }
 func testProtectedAncestor() throws { let f=try file("credentials/key"); let p=PathPolicy(roots:[root],protected:[f]); XCTAssertThrowsError(try p.validate(f)); XCTAssertThrowsError(try p.validate(f.deletingLastPathComponent())) }
 func testOwnershipRefusal() throws { let f=try file("owned"); XCTAssertThrowsError(try PathPolicy(roots:[root],uid:getuid()+1).validate(f)) }
 func testSymlinkAncestorRefusal() throws { let f=try file("real/file"); let link=root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:f.deletingLastPathComponent()); XCTAssertThrowsError(try PathPolicy(roots:[root]).validate(link.appendingPathComponent("file"))) }
 func testSymlinkOutsidePartial() throws { let d=root.appendingPathComponent("folder"); try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true); try FileManager.default.createSymbolicLink(at:d.appendingPathComponent("outside"),withDestinationURL:URL(fileURLWithPath:"/etc")); let m=try FileScanner.measure(d); XCTAssertFalse(m.complete); XCTAssertEqual(m.files,0) }
 func testContainedBundleSymlink() throws { let f=try file("bundle/Versions/A/binary"); let bundle=root.appendingPathComponent("bundle"); try FileManager.default.createSymbolicLink(at:bundle.appendingPathComponent("Current"),withDestinationURL:f.deletingLastPathComponent()); let m=try FileScanner.measure(bundle); XCTAssertTrue(m.complete); XCTAssertEqual(m.files,1) }
 func testHardlinkSizing() throws { let f=try file("folder/a"); try FileManager.default.linkItem(at:f,to:root.appendingPathComponent("folder/b")); let m=try FileScanner.measure(f.deletingLastPathComponent()); XCTAssertEqual(m.logical,8192); XCTAssertEqual(m.files,1); XCTAssertFalse(m.hasExternalLinks); XCTAssertTrue(try FileScanner.measure(f).hasExternalLinks) }
 func testBoundedScanAndExclusions() throws { _=try file("folder/a"); _=try file("folder/b"); let d=root.appendingPathComponent("folder"); XCTAssertFalse(try FileScanner.measure(d,limits:ScanLimits(nodes:1,seconds:5)).complete); XCTAssertFalse(try FileScanner.measure(d,exclusions:[d.appendingPathComponent("a").path]).complete) }
 func testCancellation() async throws { for i in 0..<50 { _=try file("folder/\(i)") }; let d=root!; let task=Task { try Task.checkCancellation(); return try FileScanner.measure(d) }; task.cancel(); do { _=try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) } }
 func testPreviewDoesNotMutate() async throws { let f=try file("preview"); let outcomes=await TrashService.perform([try item(f)],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(outcomes.first?.status,"Preview"); XCTAssertTrue(FileManager.default.fileExists(atPath:f.path)) }
 func testStaleFileSkipped() async throws { let f=try file("stale"); let original=try item(f); try Data("changed".utf8).write(to:f); let result=await TrashService.perform([original],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(result.first?.status,"Skipped") }
 func testChangedNestedFile() async throws { let f=try file("folder/nested/file"); let original=try item(root.appendingPathComponent("folder")); try Data("changed".utf8).write(to:f); let result=await TrashService.perform([original],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(result.first?.status,"Skipped") }
 func testRunningAppRefused() async throws { let f=try file("running"); let result=await TrashService.perform([try item(f,ids:["test.app"])],policy:PathPolicy(roots:[root]),runningIDs:{["test.app"]},dryRun:true); XCTAssertEqual(result.first?.status,"Skipped") }
 func testNestedSelectionsRefused() async throws { let f=try file("folder/file"); let result=await TrashService.perform([try item(f.deletingLastPathComponent()),try item(f)],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(result.last?.status,"Skipped") }
 func testItemizedRemovalAndRecovery() async throws {
  let a=try file("a"); let b=try file("b"); let plans=[try item(a),try item(b)]; let destination=root.appendingPathComponent("fixture-trash"); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
  let result=await TrashService.perform(plans,policy:PathPolicy(roots:[root]),runningIDs:{[]},mover:{ url in let target=destination.appendingPathComponent(url.lastPathComponent); try FileManager.default.moveItem(at:url,to:target); return target })
  XCTAssertEqual(result.map(\.status),["Trashed","Trashed"]); XCTAssertNotNil(result[0].recovery); XCTAssertFalse(FileManager.default.fileExists(atPath:a.path)); XCTAssertTrue(FileManager.default.fileExists(atPath:destination.appendingPathComponent("a").path))
 }
 func testPartialUninstallOutcome() async throws { let a=try file("App.app/Contents/file"); let data=try file("data"); let app=try item(a.deletingLastPathComponent().deletingLastPathComponent()); let related=try item(data); try Data("changed".utf8).write(to:data); let result=await TrashService.perform([app,related],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(result.map(\.status),["Preview","Skipped"]) }
 func testExactAssociatedDataAndSharedCopyProtection() throws {
  let app=root.appendingPathComponent("Example.app"); try FileManager.default.createDirectory(at:app.appendingPathComponent("Contents"),withIntermediateDirectories:true)
  let plist:[String:Any]=["CFBundleIdentifier":"app.bonsai.fixture","CFBundleName":"Example","CFBundleShortVersionString":"1.2"]
  try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
  _=try file("Library/Caches/app.bonsai.fixture/data"); _=try file("Library/Caches/app.bonsai.fixture.unrelated/data")
  let inventory=try AppInventory.scan(roots:[app]); XCTAssertEqual(inventory.count,1); XCTAssertEqual(inventory[0].version,"1.2")
  let paths=try AppInventory.associated(inventory[0],inventory:inventory,home:root)
  XCTAssertEqual(paths.count,2); XCTAssertFalse(paths.contains { $0.id.contains("unrelated") })
  let copy=root.appendingPathComponent("Copy.app"); try FileManager.default.copyItem(at:app,to:copy)
  let shared=try AppInventory.scan(roots:[app,copy]); XCTAssertEqual(try AppInventory.associated(shared[0],inventory:shared,home:root).count,1)
 }
 func testDependencyFolderReview() throws {
  _=try file("project/node_modules/module/index.js"); _=try file("project/.git/tracked"); let found=try CleanCatalog.dependencies(in:root.appendingPathComponent("project")); XCTAssertEqual(found.count,1); XCTAssertEqual(found[0].risk,"High"); XCTAssertEqual(found[0].category,"Dependency folders")
 }
 func testStaleParentIdentity() async throws {
  let file=try file("folder/file"); let plan=try item(file); let folder=file.deletingLastPathComponent(); let renamed=root.appendingPathComponent("renamed"); try FileManager.default.moveItem(at:folder,to:renamed); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); try FileManager.default.moveItem(at:renamed.appendingPathComponent("file"),to:file)
  let result=await TrashService.perform([plan],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true); XCTAssertEqual(result[0].status,"Skipped"); XCTAssertTrue(result[0].detail.contains("Parent"))
 }
 func testMissingPermission() throws { let d=root.appendingPathComponent("denied"); try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true); try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:d.path); defer { try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:d.path) }; XCTAssertFalse(try FileScanner.measure(d).complete) }
 func processFixture(_ pid:Int32,name:String="Example",uid:UInt32=501,start:UInt64=10,parent:Int32=1,path:String="",memory:UInt64=100,cpu:Double=2,available:Bool=true,cpuAvailable:Bool=true)->ProcessSample {
  ProcessSample(pid:pid,uid:uid,start:start,startMicro:0,name:name,memory:memory,cpu:cpu,cpuNS:1000,parentPID:parent,executable:path,metricsAvailable:available,cpuAvailable:cpuAvailable)
 }
 func testProcessGroupsEmbeddedHelpersAndAggregates() {
  let app=processFixture(100,path:"/Applications/Example.app/Contents/MacOS/Example",memory:400,cpu:4)
  let helper=processFixture(101,name:"Renderer",start:11,path:"/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",memory:600,cpu:120)
  let external=processFixture(102,name:"Worker",start:12,parent:100,path:"/usr/bin/worker",memory:200,cpu:2)
  let records=[ProcessApplication(pid:100,url:URL(fileURLWithPath:"/Applications/Example.app"),name:"Example Browser")]
  let groups=ProcessGrouping.groups([app,helper,external,helper],applications:records)
  XCTAssertEqual(groups.count,1);let g=groups[0];XCTAssertEqual(g.members.count,3);XCTAssertEqual(g.name,"Example Browser");XCTAssertEqual(g.representative.pid,100);XCTAssertEqual(g.memory,1200);XCTAssertEqual(g.cpu,126);XCTAssertTrue(g.memoryComplete);XCTAssertTrue(g.cpuComplete)
 }
 func testProcessGroupsKeepCopiesOwnersAndNamesSeparate() {
  let samples=[processFixture(10,path:"/Applications/Example.app/Contents/MacOS/Example"),processFixture(11,uid:502,path:"/Applications/Example.app/Contents/MacOS/Example"),processFixture(12,path:"/Users/test/Example.app/Contents/MacOS/Example"),processFixture(13,name:"Example Helper",path:"/usr/bin/helper"),processFixture(14,name:"Example Helper",path:"/usr/bin/helper")]
  let groups=ProcessGrouping.groups(samples)
  XCTAssertEqual(groups.count,5);XCTAssertEqual(Set(groups.map(\.id)).count,5)
  XCTAssertNil(ProcessGrouping.applicationURL(executable:"/Applications/Example.app-other/helper"))
  XCTAssertNil(ProcessGrouping.applicationURL(executable:"/Applications/Example.app/../Other/helper"))
  XCTAssertNil(ProcessGrouping.applicationURL(executable:"Example.app/helper"))
 }
 func testProcessAncestryRejectsWrongOwnerNewParentAndCycles() {
  let app=processFixture(10,start:20,path:"/Applications/Example.app/Contents/MacOS/Example")
  let old=processFixture(11,start:10,parent:10,path:"/usr/bin/worker")
  let other=processFixture(12,uid:502,start:22,parent:10,path:"/usr/bin/worker")
  let cycleA=processFixture(13,start:30,parent:14,path:"/usr/bin/a"),cycleB=processFixture(14,start:30,parent:13,path:"/usr/bin/b")
  let differentApp=processFixture(15,start:24,parent:10,path:"/Applications/Other.app/Contents/MacOS/Other")
  let groups=ProcessGrouping.groups([app,old,other,cycleA,cycleB,differentApp])
  XCTAssertEqual(groups.count,6);XCTAssertTrue(groups.allSatisfy {$0.members.count==1})
  let reused=processFixture(10,name:"New",start:40,path:"/usr/bin/new")
  let again=ProcessGrouping.groups([app,reused,old]);XCTAssertEqual(again.count,2);XCTAssertTrue(again.contains {$0.name=="New"});XCTAssertTrue(again.allSatisfy {$0.applicationURL==nil})
 }
 func testProcessUnknownMetricsAndSaturatingTotals() {
  let app=processFixture(10,path:"/Applications/Example.app/a",memory:UInt64.max,cpu:Double.nan)
  let helper=processFixture(11,start:11,path:"/Applications/Example.app/b",memory:99,cpu:3)
  let unknown=processFixture(12,start:12,path:"/Applications/Example.app/c",memory:900,cpu:900,available:false,cpuAvailable:false)
  let g=ProcessGrouping.groups([app,helper,unknown])[0]
  XCTAssertEqual(g.memory,UInt64.max);XCTAssertEqual(g.cpu,3);XCTAssertFalse(g.memoryComplete);XCTAssertFalse(g.cpuComplete);XCTAssertTrue(g.hasMemory);XCTAssertTrue(g.hasCPU)
  let missing=ProcessGrouping.groups([processFixture(20,available:false,cpuAvailable:false)])[0]
  XCTAssertFalse(missing.hasMemory);XCTAssertFalse(missing.hasCPU);XCTAssertEqual(missing.memory,0)
 }
 func testProcessSearchSortingAndPins() {
  let groups=ProcessGrouping.groups([processFixture(10,name:"Alpha",memory:100,cpu:4),processFixture(11,name:"Beta",memory:200,cpu:2),processFixture(12,name:"Unknown",available:false,cpuAvailable:false)])
  func shown(_ sort:ProcessSortKey,_ asc:Bool,_ pins:Set<String>=[],query:String="")->[ProcessGroup] {ProcessGrouping.presented(groups,query:query,sort:sort,ascending:asc,pinned:pins)}
  XCTAssertEqual(shown(.memory,false).map(\.name),["Beta","Alpha","Unknown"])
  XCTAssertEqual(shown(.memory,true).map(\.name),["Alpha","Beta","Unknown"])
  XCTAssertEqual(shown(.cpu,false).map(\.name),["Alpha","Beta","Unknown"])
  XCTAssertEqual(shown(.name,false).map(\.name),["Unknown","Beta","Alpha"])
  let alpha=groups.first {$0.name=="Alpha"}!;XCTAssertEqual(shown(.memory,false,[alpha.pinKey]).first?.name,"Alpha")
  XCTAssertEqual(shown(.pid,true,query:"11").map(\.name),["Beta"])
  let helper=processFixture(21,name:"Special Renderer",start:11,path:"/Applications/App.app/helper")
  let app=processFixture(20,path:"/Applications/App.app/main")
  let result=ProcessGrouping.presented(ProcessGrouping.groups([app,helper]),query:"Special Renderer",sort:.name,ascending:true,pinned:[])
  XCTAssertEqual(result.count,1);XCTAssertEqual(result[0].members.count,2)
 }
 func testProcessGroupStableIdentityAndIncompleteSnapshot() {
  let first=processFixture(10,path:"/Applications/App.app/main")
  let next=processFixture(20,start:100,path:"/Applications/App.app/main")
  let a=ProcessGrouping.groups([first])[0],b=ProcessGrouping.groups([next])[0]
  XCTAssertEqual(a.id,b.id);XCTAssertEqual(a.pinKey,b.pinKey)
  let unknown=processFixture(30,name:"Registered",path:"")
  let info=[ProcessApplication(pid:30,url:URL(fileURLWithPath:"/Applications/Registered.app"),name:"Registered App")]
  XCTAssertEqual(ProcessGrouping.groups([unknown],applications:info)[0].name,"Registered App")
  XCTAssertNil(ProcessGrouping.groups([unknown],applications:[ProcessApplication(pid:30,url:URL(string:"https://example.com/Remote.app")!,name:"Remote")])[0].applicationURL)
 }
 func testRatesResetsAndInterfaces() { let old=CounterSample(time:10,counters:["en0":(100,100),"utun0":(300,300)]); let new=CounterSample(time:12,counters:["en0":(300,200),"utun0":(1,1),"en1":(10,20)]); let rates=RateCalculator.rates(previous:old,current:new); XCTAssertEqual(rates.count,1); XCTAssertEqual(rates[0].download,100); XCTAssertEqual(rates[0].upload,50); XCTAssertTrue(RateCalculator.rates(previous:old,current:CounterSample(time:10,counters:new.counters)).isEmpty); XCTAssertTrue(RateCalculator.rates(previous:old,current:CounterSample(time:50,counters:new.counters)).isEmpty) }
 func testLoginInventoryParsingAndBoundaries() {
  let text="""
  Records for UID 502
  #1:
  UUID: other
  Name: Other user
  Type: app (0x2)
  Disposition: [enabled, allowed, visible]
  Records for UID 501
  #1:
  UUID: login
  Name: Fixture Login
  Type: app (0x2)
  Identifier: app.fixture.login
  URL: file:///Applications/Fixture.app
  Disposition: [enabled, allowed, visible, notified] (11)
  #2:
  UUID: background
  Name: Fixture Background
  Type: login item (0x4)
  Disposition: [disabled, allowed, not visible]
  URL: https://example.com
  #3:
  UUID: vendor
  Name: Vendor container
  Type: developer (0x20)
  Disposition: [enabled, allowed, visible]
  #4:
  UUID: unknown
  Name: Unknown state
  Type: agent (0x8)
  Disposition: changed output format
  """
  let result=LoginItemInventory.parse(text,uid:501)
  XCTAssertEqual(result.entries.count,3)
  let login=result.entries.first {$0.id=="btm:login"}!
  XCTAssertEqual(login.enabled,true);XCTAssertEqual(login.section,"Login items");XCTAssertEqual(login.owner,501)
  let background=result.entries.first {$0.id=="btm:background"}!
  XCTAssertEqual(background.enabled,false);XCTAssertNil(background.url)
  XCTAssertNil(result.entries.first {$0.id=="btm:unknown"}!.enabled)
  XCTAssertTrue(LoginItemInventory.parse("permission denied",uid:501).entries.isEmpty)
  XCTAssertTrue(LoginItemInventory.parse("",uid:501).note.contains("not proof"))
 }
 func testModernLoginGroupingPathsAndNegativeUID() {
  let text="""
  Records for UID -501
  #1:
  UUID: wrong
  Name: Wrong user
  Type: app (0x2)
  Disposition: [enabled, allowed]
  Records for UID 501
  #1:
  UUID: login
  Name: Open at Login
  Identifier: 2.app.login
  Type: app (0x2)
  Disposition: [enabled, allowed, notified] (0xb)
  URL: /Applications/Login.app
  #2:
  UUID: app
  Name: Background App
  Identifier: 2.app.background
  Type: app (0x2)
  Disposition: [disabled, allowed, notified] (0xa)
  URL: /Applications/Background.app
  #3:
  UUID: helper
  Name: Background Helper
  Identifier: 4.app.helper
  Parent Identifier: 2.app.background
  Type: login item (0x4)
  Disposition: [enabled, allowed, notified]
  URL: Contents/Library/LoginItems/Helper.app
  #4:
  UUID: agent
  Name: Updater
  Identifier: 8.app.updater
  Parent Identifier: 2.app.background
  Type: agent (0x8)
  Disposition: [enabled, allowed]
  URL: Contents/Library/LaunchAgents/Updater.plist
  #5:
  UUID: escape
  Name: Escape
  Parent Identifier: 2.app.background
  Type: agent (0x8)
  Disposition: [enabled, allowed]
  URL: Contents/../../Other.app
  """
  let items=LoginItemInventory.parse(text,uid:501).entries
  XCTAssertEqual(items.count,4);XCTAssertFalse(items.contains {$0.name=="Wrong user" || $0.name=="Background Helper"})
  let login=items.first {$0.id=="btm:login"}!;XCTAssertEqual(login.section,"Login items");XCTAssertEqual(login.url?.path,"/Applications/Login.app")
  let bg=items.first {$0.id=="btm:app"}!;XCTAssertEqual(bg.section,"Allow in the background");XCTAssertEqual(bg.enabled,true);XCTAssertTrue(bg.details.contains("Background Helper"))
  XCTAssertEqual(items.first {$0.id=="btm:agent"}!.url?.path,"/Applications/Background.app/Contents/Library/LaunchAgents/Updater.plist")
  XCTAssertNil(items.first {$0.id=="btm:escape"}!.url)
  XCTAssertEqual(items.first {$0.id=="btm:agent"}!.launchLabel,"app.updater");XCTAssertNil(bg.launchLabel)
 }
 func testProtectionRuntimeProtectionAndIntegrity() async throws {
  let source=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/ProtectionBackend")
  let protected=try await ProtectionBackend.protectedIdentifiers(["com.apple.finder","app.bonsai.fixture","com.crowdstrike.falcon","com.apple.dt.Xcode"],directory:source)
  XCTAssertEqual(protected,Set(["com.apple.finder","com.crowdstrike.falcon"]))
  do {_=try await ProtectionBackend.protectedIdentifiers(["bad;command"],directory:source);XCTFail()} catch {XCTAssertTrue(error is BonsaiError)}
  let copy=root.appendingPathComponent("backend");try FileManager.default.copyItem(at:source,to:copy)
  try Data("tampered".utf8).write(to:copy.appendingPathComponent("protection.sh"))
  XCTAssertThrowsError(try ProtectionBackend.validatedScript(directory:copy))
  XCTAssertFalse(CommandRunner.allowed.contains("/bin/bash"))
 }
 func testStartupMutationAndRestorationFixtures() async throws {
  let f=try file("agent.plist"),identity=try Identity.read(f)
  let item=StartupItem(url:f,label:"app.bonsai.fixture",owner:getuid(),source:"User LaunchAgent",loaded:true,disabled:false,command:"fixture only",identity:identity)
  let probe=StartupFixtureExecutor()
  let result=await StartupService.set(item,disabled:true,policy:PathPolicy(roots:[root]),protect:{_ in []},execute:{path,args,_ in await probe.run(path,args)})
  XCTAssertEqual(result.status,"Changed")
  XCTAssertTrue(result.detail.contains("launchctl enable"));XCTAssertTrue(result.detail.contains("bootstrap"))
  let calls=await probe.calls();XCTAssertEqual(calls.map {$0.first!},["print-disabled","disable","bootout","print-disabled"])
  XCTAssertTrue(calls.allSatisfy {!$0.contains("system")})
  let stale=await StartupService.set(item,disabled:true,policy:PathPolicy(roots:[root]),protect:{_ in []},execute:{path,args,_ in await probe.run(path,args)})
  XCTAssertEqual(stale.status,"Failed");XCTAssertTrue(stale.detail.contains("changed since review"))
  let guardProbe=StartupFixtureExecutor()
  let blocked=await StartupService.set(item,disabled:true,policy:PathPolicy(roots:[root]),protect:{_ in ["app.bonsai.fixture"]},execute:{path,args,_ in await guardProbe.run(path,args)})
  XCTAssertEqual(blocked.status,"Failed");let blockedCalls=await guardProbe.calls();XCTAssertTrue(blockedCalls.isEmpty)
  let off=StartupItem(url:f,label:item.label,owner:getuid(),source:item.source,loaded:false,disabled:true,command:item.command,identity:identity)
  let restored=await StartupService.set(off,disabled:false,policy:PathPolicy(roots:[root]),protect:{_ in []},execute:{path,args,_ in await probe.run(path,args)})
  XCTAssertEqual(restored.status,"Changed");let restoredCalls=await probe.calls();XCTAssertTrue(restoredCalls.contains { $0.first=="bootstrap" })
 }
 func testBrewParsing() throws { let data=Data(#"{"casks":[{"name":"firefox","installed_versions":["1"],"current_version":"2"},{"name":";rm"}]}"#.utf8); let value=try UpdateService.parseBrew(data); XCTAssertEqual(value.count,1); XCTAssertEqual(value[0].installed,"1"); XCTAssertEqual(value[0].available,"2") }
 func testNoNetworkWithoutConsent() async { do { _=try await UpdateService.check(consent:false); XCTFail() } catch { XCTAssertTrue(error is BonsaiError) } }
 func testStartupStateParsing() { XCTAssertEqual(StartupService.parseDisabled("disabled services = {\n\"app.test\" => true\n}",label:"app.test"),true); XCTAssertEqual(StartupService.parseDisabled("disabled services = {}",label:"app.test"),false); XCTAssertNil(StartupService.parseDisabled("permission denied",label:"app.test")) }
 func testStartupRestorationPlan() throws {
  let f=try file("agent.plist"); let i=try Identity.read(f)
  let original=StartupItem(url:f,label:"app.bonsai.fixture",owner:getuid(),source:"User LaunchAgent",loaded:true,disabled:false,command:"/usr/bin/true",identity:i)
  let enabled=StartupService.restorationCommands(original); XCTAssertEqual(enabled[0][0],"enable"); XCTAssertEqual(enabled[1][0],"bootstrap"); XCTAssertEqual(enabled[1].last,f.path)
  let off=StartupItem(url:f,label:"app.bonsai.fixture",owner:getuid(),source:"User LaunchAgent",loaded:false,disabled:true,command:"/usr/bin/true",identity:i)
  XCTAssertEqual(StartupService.restorationCommands(off).map { $0[0] },["disable","bootout"])
 }
 func testLargestFilesRanksNestedFilesWithoutFollowingLinks() throws {
  let small=try file("largest/small",8192),medium=try file("largest/medium",65536),large=try file("largest/nested/large",131072)
  let outside=try file("outside-large",524288),tree=root.appendingPathComponent("largest")
  try FileManager.default.createSymbolicLink(at:tree.appendingPathComponent("linked-file"),withDestinationURL:outside)
  try FileManager.default.createSymbolicLink(at:tree.appendingPathComponent("linked-folder"),withDestinationURL:root)
  let found=try LargestDiskFiles.scan(roots:[tree,tree],limit:2)
  XCTAssertTrue(found.complete);XCTAssertEqual(found.entries.map(\.url),[large,medium].map(physicalURL))
  XCTAssertFalse(found.entries.contains {$0.url==physicalURL(small) || $0.url==physicalURL(outside) || $0.directory})
  XCTAssertTrue(found.entries.allSatisfy {$0.measurement.files==1 && $0.measurement.manifest[$0.id] != nil})
  let limited=try LargestDiskFiles.scan(roots:[tree],limits:ScanLimits(nodes:1,seconds:10))
  XCTAssertFalse(limited.complete);XCTAssertTrue(limited.entries.isEmpty)
 }
 func testDiskRemainderTileHasFixedCompactSize() {
  let bounds=CGRect(x:12,y:24,width:900,height:600)
  let small=Treemap.diskLayout([100,80,60,40,30,20,10,5,1],remainder:8,in:bounds)
  let large=Treemap.diskLayout([100,80,60,40,30,20,10,5,1_000_000],remainder:8,in:bounds)
  XCTAssertEqual(small.count,9);XCTAssertEqual(large.count,9)
  XCTAssertEqual(small.first {$0.index==8}?.rect,large.first {$0.index==8}?.rect)
  XCTAssertEqual(large.first {$0.index==8}?.rect.size,CGSize(width:220,height:220))
  for tiles in [small,large,Treemap.diskLayout([8,7,6,5,4,3,2,1,50],remainder:8,in:CGRect(x:0,y:0,width:320,height:200)),Treemap.diskLayout([8,7,6,5,4,3,2,1,50],remainder:8,in:CGRect(x:0,y:0,width:200,height:320))] {
   XCTAssertEqual(tiles.first {$0.index==8}?.rect.width,tiles.first {$0.index==8}?.rect.height)
   XCTAssertEqual(Set(tiles.map(\.index)).count,9)
   for (offset,tile) in tiles.enumerated() {
    XCTAssertTrue(tile.rect.width>0 && tile.rect.height>0)
    for other in tiles.dropFirst(offset+1) {let overlap=tile.rect.intersection(other.rect);XCTAssertTrue(overlap.isNull || overlap.width*overlap.height<0.001)}
   }
  }
  XCTAssertEqual(Treemap.diskLayout([10,5],remainder:nil,in:bounds).count,2)
 }
 func testReadableTreemapCapsDominanceAndKeepsTilesVisible() {
  let box=CGRect(x:12,y:8,width:800,height:500)
  for weights in [[1e12,1,2,3,4,5,6,7,8],[1e12,1],[10,10,10,10],[0,1,Double.nan,2,Double.infinity]] {
   let tiles=Treemap.readableLayout(weights,in:box)
   XCTAssertEqual(tiles.count,weights.filter {$0>0 && $0.isFinite}.count)
   var area:CGFloat=0
   for tile in tiles {let share=tile.rect.width*tile.rect.height/(box.width*box.height);XCTAssertTrue(share<=0.55000001);XCTAssertTrue(share>=0.04499999);XCTAssertTrue(box.contains(tile.rect));area+=tile.rect.width*tile.rect.height
    for other in tiles where other.index != tile.index {XCTAssertTrue(tile.rect.intersection(other.rect).isNull || tile.rect.intersection(other.rect).isEmpty)}
   }
   XCTAssertEqual(area,box.width*box.height,accuracy:0.01)
  }
  let single=Treemap.readableLayout([42],in:box)[0]
  XCTAssertEqual(single.rect.width*single.rect.height,box.width*box.height*0.55,accuracy:0.01)
  XCTAssertEqual(single.rect.midX,box.midX,accuracy:0.01)
  XCTAssertTrue(Treemap.readableLayout([0,-1,.nan],in:box).isEmpty)
 }
 func testMenuPanelPlacementStaysOnClickedDisplay() {
  let display=CGRect(x:-1440,y:100,width:1440,height:900)
  let frame=MenuPanelPlacement.frame(anchor:CGRect(x:-70,y:1000,width:30,height:24),visible:display,size:CGSize(width:392,height:840))
  XCTAssertTrue(display.contains(frame));XCTAssertEqual(frame.maxX,display.maxX-8,accuracy:0.01)
  XCTAssertTrue(frame.maxY<1000)
  let limited=MenuPanelPlacement.frame(anchor:CGRect(x:-1400,y:1000,width:20,height:24),visible:display,size:CGSize(width:5000,height:5000))
  XCTAssertTrue(display.contains(limited));XCTAssertEqual(limited.width,display.width-16);XCTAssertEqual(limited.height,display.height-16)
 }
 func testDiskInvalidationDoesNotWaitForWalkOrSaveStaleCache() async throws {
  let original=try file("original",8192),explorer=DiskExplorer()
  let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
  let root=self.root!
  let task=Task {try await explorer.scan(root,refresh:true,progress:{_,count,_ in if count==1 {entered.signal();_=release.wait(timeout:.now()+3)}})}
  defer {release.signal();task.cancel()}
  let ready=await Task.detached {entered.wait(timeout:.now()+2) == .success}.value
  XCTAssertTrue(ready)
  let began=ProcessInfo.processInfo.systemUptime
  await explorer.invalidate()
  XCTAssertTrue(ProcessInfo.processInfo.systemUptime-began<0.5)
  try Data(repeating:1,count:32768).write(to:original)
  release.signal();_=try await task.value
  let cached=await explorer.saved(root);XCTAssertNil(cached)
  let fresh=try await explorer.scan(root)
  XCTAssertEqual(fresh.total,try DiskTreeScanner.measure(original,limits:ScanLimits()).allocated)
 }
 func testTreemapProportionalNonoverlapping() { let r=CGRect(x:0,y:0,width:600,height:400); let tiles=Treemap.layout([6,3,1,0],in:r); XCTAssertEqual(tiles.count,3); for tile in tiles { XCTAssertEqual(tile.rect.width*tile.rect.height,CGFloat([6.0,3,1][tile.index]/10)*r.width*r.height,accuracy:0.01); XCTAssertTrue(r.contains(tile.rect)) }; for a in tiles { for b in tiles where a.index != b.index { XCTAssertTrue(a.rect.intersection(b.rect).isNull || a.rect.intersection(b.rect).isEmpty) } } }
 func testCommandFailureTimeoutAndCancellation() async throws { let began=ProcessInfo.processInfo.systemUptime; let failed=try await CommandRunner.run("/usr/bin/false",[]); XCTAssertFalse(failed.succeeded); let timeout=try await CommandRunner.run("/bin/sleep",["5"],timeout:0.05); XCTAssertTrue(timeout.timedOut); let task=Task { try await CommandRunner.run("/bin/sleep",["5"],timeout:10) }; try await Task.sleep(nanoseconds:50_000_000); task.cancel(); let cancelled=try await task.value; XCTAssertTrue(cancelled.cancelled); XCTAssertTrue(ProcessInfo.processInfo.systemUptime-began < 5) }
 func testCommandCapturedOutput() async throws { let result=try await CommandRunner.run("/usr/bin/qlmanage",["-h"],timeout:5); XCTAssertTrue((result.standardOutput+result.standardError).contains("qlmanage")); XCTAssertEqual(result.output,result.standardOutput+result.standardError); XCTAssertFalse(result.timedOut) }
 func testCommandConcurrentCompletions() async throws { let began=ProcessInfo.processInfo.systemUptime; async let first=CommandRunner.run("/usr/bin/true",[]); async let second=CommandRunner.run("/usr/bin/false",[]); let (a,b)=try await (first,second); XCTAssertTrue(a.succeeded); XCTAssertFalse(b.succeeded); XCTAssertTrue(ProcessInfo.processInfo.systemUptime-began < 5) }
 func testCommandAllowlist() async { do { _=try await CommandRunner.run("/bin/sh",["-c","echo no"]); XCTFail() } catch { XCTAssertTrue(error is BonsaiError) } }
 func testAuditSanitizationAndPermissions() async throws { let url=root.appendingPathComponent("audit/history.json"); let store=AuditStore(url:url); try await store.append(AuditEntry(operation:"Test",outcomes:[ItemOutcome(title:"test",path:FileManager.default.homeDirectoryForCurrentUser.path+"/private",status:"Preview",detail:"line\u{01}clean")])); let values=await store.read(); XCTAssertEqual(values[0].outcomes[0].path,"~/private"); XCTAssertEqual(values[0].outcomes[0].detail,"lineclean"); let perms=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? Int; XCTAssertEqual(perms,0o600) }
 func testSavedDiskMapSurvivesNewExplorerAndRefreshesExplicitly() async throws {
  let location=root.appendingPathComponent("files"),f=try file("files/a")
  let storage=DiskScanCache(directory:root.appendingPathComponent("cache"))
  let first=try await DiskExplorer(storage:storage).scan(location)
  try Data(repeating:42,count:50000).write(to:f)
  let restarted=DiskExplorer(storage:storage),saved=try await restarted.scan(location)
  XCTAssertEqual(saved.date,first.date);XCTAssertEqual(saved.total,first.total)
  let fresh=try await restarted.scan(location,refresh:true);XCTAssertGreaterThan(fresh.total,saved.total)
  await restarted.invalidate();XCTAssertTrue(storage.load().isEmpty)
 }
 func testSavedDiskMapAgeIdentityAndMalformedData() async throws {
  let location=root.appendingPathComponent("files");_=try file("files/a")
  let storage=DiskScanCache(directory:root.appendingPathComponent("cache")),scan=try await DiskExplorer(storage:storage).scan(location)
  XCTAssertEqual(storage.load().count,1);XCTAssertTrue(storage.load(now:scan.date.addingTimeInterval(8*86400)).isEmpty)
  XCTAssertTrue(storage.load(now:scan.date.addingTimeInterval(-120)).isEmpty)
  try FileManager.default.moveItem(at:location.appendingPathComponent("a"),to:location.appendingPathComponent("old"));_=try file("files/a")
  XCTAssertTrue(storage.load().isEmpty)
  try Data("invalid cache".utf8).write(to:storage.directory.appendingPathComponent("maps-v1.json"));XCTAssertTrue(storage.load().isEmpty)
 }
 func testDiskMapCacheRejectsSymbolicFilesAndParents() async throws {
  let location=root.appendingPathComponent("files");_=try file("files/a")
  let real=root.appendingPathComponent("real-cache"),storage=DiskScanCache(directory:real)
  let scan=try await DiskExplorer().scan(location);storage.save([scan]);XCTAssertEqual(storage.load().count,1)
  let link=root.appendingPathComponent("linked-cache");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:real)
  let linked=DiskScanCache(directory:link);XCTAssertTrue(linked.load().isEmpty);linked.save([scan]);linked.remove();XCTAssertEqual(storage.load().count,1)
  let file=real.appendingPathComponent("maps-v1.json"),outside=try self.file("outside.json")
  try FileManager.default.removeItem(at:file);try FileManager.default.createSymbolicLink(at:file,withDestinationURL:outside)
  XCTAssertTrue(storage.load().isEmpty);storage.save([scan]);storage.remove();XCTAssertEqual(try Data(contentsOf:outside).count,8192)
 }
 func testDiskMapCacheOwnerOnlyPermissionsAndBounds() async throws {
  let location=root.appendingPathComponent("files");_=try file("files/a")
  let storage=DiskScanCache(directory:root.appendingPathComponent("cache")),scan=try await DiskExplorer().scan(location)
  storage.save(Array(repeating:scan,count:20));XCTAssertEqual(storage.load().count,8)
  let identity=try Identity.read(storage.directory.appendingPathComponent("maps-v1.json"));XCTAssertEqual(identity.mode & 0o777,0o600)
 }
 func testDiskDrilldownUsesExistingChildMeasurement() async throws {
  _=try file("files/group/a");_=try file("files/group/b")
  let explorer=DiskExplorer(),location=root.appendingPathComponent("files"),group=location.appendingPathComponent("group")
  _=try await explorer.scan(location)
  let saved=await explorer.saved(group);XCTAssertNotNil(saved);XCTAssertEqual(saved?.entries.count,2)
  let cached=try await explorer.scan(group),fresh=try await explorer.scan(group,refresh:true)
  XCTAssertEqual(cached.date,saved?.date);XCTAssertEqual(cached.total,fresh.total)
  XCTAssertEqual(cached.entries.map(\.measurement.allocated).sorted(),fresh.entries.map(\.measurement.allocated).sorted())
 }
 func testDiskChildSummaryHardlinksAcrossFoldersMatchFreshAccounting() async throws {
  let a=try file("files/group/left/a"),b=root.appendingPathComponent("files/group/right/b")
  try FileManager.default.createDirectory(at:b.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.linkItem(at:a,to:b)
  let explorer=DiskExplorer(),group=root.appendingPathComponent("files/group")
  _=try await explorer.scan(group.deletingLastPathComponent())
  let saved=try await explorer.scan(group),fresh=try await explorer.scan(group,refresh:true)
  XCTAssertEqual(saved.total,fresh.total);XCTAssertEqual(saved.entries.count,2)
  XCTAssertEqual(saved.entries.reduce(0) {$0+$1.measurement.allocated},fresh.entries.reduce(0) {$0+$1.measurement.allocated})
 }
 func testExplorerCacheAndRefresh() async throws { let f=try file("a"); let explorer=DiskExplorer(); let first=try await explorer.scan(root); try Data(repeating:0,count:50000).write(to:f); let cached=try await explorer.scan(root); XCTAssertEqual(first.date,cached.date); let fresh=try await explorer.scan(root,refresh:true); XCTAssertGreaterThan(fresh.total,first.total) }

 func testDiskCrossEntryHardlinksAndGrouping() async throws {
  let a=try file("a"),b=root.appendingPathComponent("b");try FileManager.default.linkItem(at:a,to:b)
  let scan=try await DiskExplorer().scan(root)
  XCTAssertEqual(scan.entries.count,2);XCTAssertEqual(scan.total,scan.entries[0].measurement.allocated)
  XCTAssertEqual(scan.entries.reduce(0) {$0+$1.measurement.allocated},scan.total*2)
  var entries=scan.entries
  for i in 0..<20 {var size=Measurement();size.allocated=UInt64(i+1);entries.append(DiskEntry(url:root.appendingPathComponent("extra\(i)"),directory:false,measurement:size))}
  let groups=DiskMapGroup.make(entries,maximum:8)
  XCTAssertEqual(groups.count,8);XCTAssertEqual(groups.flatMap(\.entries).count,entries.count)
  XCTAssertEqual(groups.reduce(0) {$0+$1.weight},entries.reduce(0) {$0+$1.measurement.allocated})
  XCTAssertTrue(groups.last!.entries.count>1)
 }
 func testDiskUnknownAndZeroRemainInInventory() async throws {
  _=try file("empty",0);try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("outside"),withDestinationURL:URL(fileURLWithPath:"/etc"))
  let scan=try await DiskExplorer().scan(root);XCTAssertEqual(scan.entries.count,2);XCTAssertTrue(scan.complete)
  XCTAssertEqual(scan.entries.first(where:{$0.url.lastPathComponent=="outside"})?.measurement.files,0)
  XCTAssertTrue(DiskMapGroup.make(scan.entries).isEmpty)
 }
 func testBoundedDirectoryAndChangedIdentity() throws {
  let a=try file("a");_=try file("b");_=try file("c")
  let listing=try DirectoryListing.read(root,limit:2);XCTAssertEqual(listing.urls.count,2);XCTAssertFalse(listing.complete)
  let zero=try DirectoryListing.read(root,limit:0);XCTAssertEqual(zero.urls.count,0);XCTAssertFalse(zero.complete)
  do {_=try DirectoryListing.read(root,limit:10,expected:Identity.read(a));XCTFail("Changed identity accepted")} catch {XCTAssertTrue(error is BonsaiError)}
  let link=root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:root)
  do {_=try DirectoryListing.read(link,limit:10);XCTFail("Symbolic link followed")} catch {XCTAssertEqual((error as NSError).domain,NSPOSIXErrorDomain)}
 }
 func testDiskLimitsCacheInvalidationAndScope() async throws {
  for i in 0..<8 {_=try file("f\(i)")}
  let explorer=DiskExplorer();let scan=try await explorer.scan(root,limits:ScanLimits(nodes:3,seconds:10));XCTAssertFalse(scan.complete);XCTAssertEqual(scan.entries.count,8);XCTAssertTrue(scan.entries.filter {$0.measurement.complete}.count<=3);XCTAssertFalse(scan.issues.isEmpty)
  await explorer.invalidate();let fresh=try await explorer.scan(root);XCTAssertEqual(fresh.entries.count,8);XCTAssertTrue(fresh.complete);XCTAssertEqual(fresh.scope.rawValue,"folder")
  let locations=DiskExplorer.overviewLocations(home:root);XCTAssertEqual(locations.map(\.path),[root.path,"/Applications","/Library","/opt"])
 }
 func testDiskCancellationKeepsPartialAndDoesNotCache() async throws {
  _=try file("folder/a")
  let folder=root.appendingPathComponent("folder")
  let partial=Task {while !Task.isCancelled {await Task.yield()};return try FileScanner.measure(folder,returnPartialOnCancellation:true)};partial.cancel()
  let measurement=try await partial.value;XCTAssertFalse(measurement.complete);XCTAssertTrue(measurement.issues.contains(where:{$0.contains("stopped")}))
  let explorer=DiskExplorer(),location=root!
  let scan=Task {try await explorer.scan(location)};scan.cancel()
  do {_=try await scan.value;XCTFail("Pre-cancelled scan succeeded")} catch {XCTAssertTrue(error is CancellationError)}
  let retry=try await explorer.scan(location);XCTAssertTrue(retry.complete);XCTAssertFalse(retry.wasCancelled)
 }
 func testExplorerMidScanCancellationAndRetry() async throws {
  for i in 0..<5 {_=try file("item\(i)")}
  let explorer=DiskExplorer(),location=root!
  let task=Task {try await explorer.scan(location,progress:{_,count,_ in if count==1 {withUnsafeCurrentTask {$0?.cancel()}}})}
  let stopped=try await task.value;XCTAssertTrue(stopped.wasCancelled);XCTAssertFalse(stopped.complete);XCTAssertEqual(stopped.entries.count,5);XCTAssertEqual(stopped.entries.filter {$0.measurement.complete}.count,1)
  let retry=try await explorer.scan(location);XCTAssertFalse(retry.wasCancelled);XCTAssertTrue(retry.complete);XCTAssertGreaterThan(retry.total,stopped.total)
 }
 func testFileAccessClassificationAndReadProbes() {
  XCTAssertTrue(FileAccess.isPermission(NSError(domain:NSPOSIXErrorDomain,code:Int(EACCES))))
  XCTAssertTrue(FileAccess.isPermission(NSError(domain:NSCocoaErrorDomain,code:NSFileReadUnknownError,userInfo:[NSUnderlyingErrorKey:NSError(domain:NSPOSIXErrorDomain,code:Int(EPERM))])))
  XCTAssertEqual(FileAccess.status(NSError(domain:NSPOSIXErrorDomain,code:Int(ENOENT))).rawValue,"missing")
  XCTAssertEqual(FileAccess.status(NSError(domain:NSPOSIXErrorDomain,code:Int(EIO))).rawValue,"unknown")
  let blocked=FileAccess.check(home:root,read:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(EPERM))});XCTAssertTrue(blocked.needsAccess);XCTAssertFalse(blocked.accessConfirmed);XCTAssertEqual(blocked.probes.count,3)
  let readable=FileAccess.check(home:root,read:{_ in });XCTAssertFalse(readable.needsAccess);XCTAssertTrue(readable.probes.allSatisfy {$0.status == .readable});XCTAssertTrue(readable.accessConfirmed)
  let missing=FileAccess.check(home:root,read:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(ENOENT))});XCTAssertFalse(missing.accessConfirmed)
  let unknown=FileAccess.check(home:root,read:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(EIO))});XCTAssertFalse(unknown.accessConfirmed)
 }
 func testNeededAccessRoutingAndWrappedPaths() throws {
  let denied=try file("private/data")
  let error=NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError,userInfo:[NSFilePathErrorKey:denied.path])
  let wrapped=NSError(domain:NSCocoaErrorDomain,code:NSFileReadUnknownError,userInfo:[NSUnderlyingErrorKey:error])
  XCTAssertEqual(FileAccess.deniedURL(wrapped)?.path,physicalURL(denied).path)
  XCTAssertNil(FileAccess.deniedURL(NSError(domain:NSPOSIXErrorDomain,code:Int(EIO)),fallback:denied))
  XCTAssertTrue(FileAccess.isPermission(NSError(domain:NSCocoaErrorDomain,code:NSFileWriteNoPermissionError)))
  let privateFolder=root.appendingPathComponent("private")
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:privateFolder.path)
  let locked=try Identity.read(privateFolder)
  XCTAssertEqual(FileAccessNeed(url:URL(fileURLWithPath:"/Applications/Fixture/data"),operation:"Inventory",inventory:true,uid:getuid() &+ 1,identity:locked).route,.administrator)
  XCTAssertEqual(FileAccessNeed(url:privateFolder,operation:"Clean",uid:getuid() &+ 1,identity:locked).route,.filePermissions)
  XCTAssertEqual(FileAccessNeed(url:privateFolder,operation:"Inventory",inventory:true,uid:getuid() &+ 1,identity:locked).route,.filePermissions)
  let open=try Identity.read(denied)
  XCTAssertEqual(FileAccessNeed(url:root.appendingPathComponent("Documents/data"),operation:"Clean",home:root,identity:open).route,.filesAndFolders)
  XCTAssertEqual(FileAccessNeed(url:root.appendingPathComponent("Documents-other/data"),operation:"Clean",home:root,identity:open).route,.fullDiskAccess)
 }
 func testCleanAccessDiscoveryAndRetry() throws {
  let caches=root.appendingPathComponent("Library/Caches")
  try FileManager.default.createDirectory(at:caches,withIntermediateDirectories:true)
  try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:caches.path)
  defer {try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:caches.path)}
  let blocked=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("missing-tmp"))
  XCTAssertFalse(blocked.completeWithinCatalog);XCTAssertTrue(blocked.accessDeniedPaths.contains(caches.path))
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:caches.path)
  _=try file("Library/Caches/app.fixture/generated")
  let retry=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("missing-tmp"))
  XCTAssertTrue(retry.completeWithinCatalog);XCTAssertTrue(retry.accessDeniedPaths.isEmpty);XCTAssertEqual(retry.items.count,1)
  XCTAssertEqual(try Data(contentsOf:caches.appendingPathComponent("app.fixture/generated")),Data(repeating:42,count:8192))
 }
 func testAuthorizedAppInventoryFailsClosedAndHandlesNewlines() throws {
  let app=try fixtureApp("folder/new\nline.app")
  func output(_ paths:[String],_ status:String="0")->Data {Data((paths.joined(separator:"\0")+"\0BONSAI_FIND_STATUS:"+status+"\0").utf8)}
  let parsed=try InstalledIdentifiers.parseAuthorized(output([app.id]),roots:[root],reader:{url in XCTAssertEqual(url.path,app.url.path);return app.bundleID})
  XCTAssertEqual(parsed,Set([app.bundleID]))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(output([app.id],"1"),roots:[root],reader:{_ in XCTFail("Failed inventory reached metadata reads");return nil}))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(Data([0]),roots:[root]))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(output(["/ApplicationsOther/fake.app"]),roots:[URL(fileURLWithPath:"/Applications")],reader:{_ in XCTFail("Outside path reached reader");return nil}))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(output([app.id+"/../other.app"]),roots:[root],reader:{_ in nil}))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(Data(repeating:0,count:1_048_577),roots:[root]))
  XCTAssertThrowsError(try InstalledIdentifiers.parseAuthorized(output([app.id]),roots:[root],reader:{_ in throw NSError(domain:NSPOSIXErrorDomain,code:Int(EACCES))}))
  XCTAssertThrowsError(try InstalledIdentifiers.verifyAbsent(app.bundleID,installed:parsed))
 }
 func testAuthorizedInventoryCancellationBeforeMetadata() async throws {
  let data=Data("/Applications/Fixture.app\0BONSAI_FIND_STATUS:0\0".utf8)
  let task=Task {() throws -> Set<String> in
   withUnsafeCurrentTask {$0?.cancel()}
   return try InstalledIdentifiers.parseAuthorized(data,reader:{_ in XCTFail("Cancelled inventory read metadata");return nil})
  }
  do {_=try await task.value;XCTFail("Cancelled inventory succeeded")} catch {XCTAssertTrue(error is CancellationError)}
 }
 func testScanReportsPermissionPaths() throws {
  let denied=root.appendingPathComponent("denied");try FileManager.default.createDirectory(at:denied,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:denied.path)
  defer {try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:denied.path)}
  let scan=try FileScanner.measure(root);XCTAssertFalse(scan.complete);XCTAssertTrue(scan.accessDeniedPaths?.contains(physicalURL(denied).path)==true)
 }
 func testTreemapExtremeAndInvalidWeights() {
  let rect=CGRect(x:0,y:0,width:600,height:400),weights=[Double.greatestFiniteMagnitude,Double.greatestFiniteMagnitude,Double.nan,Double.infinity,-1,0]
  let tiles=Treemap.layout(weights,in:rect);XCTAssertEqual(tiles.count,2)
  for tile in tiles {XCTAssertTrue(tile.rect.width.isFinite);XCTAssertEqual(tile.rect.width*tile.rect.height,120_000,accuracy:0.01)}
  XCTAssertTrue(Treemap.layout([1],in:CGRect(x:0,y:0,width:Double.infinity,height:1)).isEmpty)
 }
 func testPowerLifecycle() throws { let assertion=PowerAssertion(); XCTAssertFalse(assertion.active); try assertion.set(true); XCTAssertTrue(assertion.active); try assertion.set(false); XCTAssertFalse(assertion.active) }
 func testPowerObjectRelease() throws {
  var object: PowerAssertion?=PowerAssertion(); try object?.set(true); XCTAssertTrue(object?.active == true)
  weak var weakObject=object; object=nil; XCTAssertNil(weakObject)
 }
 func testDisposableProcessIdentityAndGracefulTermination() async throws {
  let child=Process();child.executableURL=URL(fileURLWithPath:"/bin/sleep");child.arguments=["10"];try child.run()
  defer {if child.isRunning {child.terminate();child.waitUntilExit()}}
  let sample=await TelemetryCollector().sample()
  guard let original=sample.processes.first(where:{$0.pid==child.processIdentifier}) else {XCTFail("Disposable child missing from telemetry");return}
  XCTAssertEqual(original.uid,getuid());XCTAssertFalse(original.executable.isEmpty);XCTAssertEqual(original.parentPID,getpid())
  let stale=ProcessSample(pid:original.pid,uid:original.uid,start:original.start+1,startMicro:original.startMicro,name:original.name,memory:0,cpu:0,cpuNS:0)
  XCTAssertThrowsError(try TelemetryCollector.terminate(stale));XCTAssertTrue(child.isRunning)
  let foreign=ProcessSample(pid:original.pid,uid:original.uid &+ 1,start:original.start,startMicro:original.startMicro,name:original.name,memory:0,cpu:0,cpuNS:0)
  XCTAssertThrowsError(try TelemetryCollector.terminate(foreign));XCTAssertTrue(child.isRunning)
  try TelemetryCollector.terminate(original)
  for _ in 0..<40 {if !child.isRunning {break};try await Task.sleep(nanoseconds:10_000_000)}
  XCTAssertFalse(child.isRunning)
 }
 func testTelemetryAndProtectedProcessControl() async throws { let c=TelemetryCollector(); let s=await c.sample(); XCTAssertGreaterThan(s.memoryTotal,0); XCTAssertGreaterThan(s.diskTotal,0); XCTAssertFalse(s.processes.isEmpty); XCTAssertEqual(s.loadAverages.count,3);XCTAssertTrue(s.loadAverages.allSatisfy {$0.isFinite && $0>=0}); if let own=s.processes.first(where:{$0.pid==getpid()}) { XCTAssertThrowsError(try TelemetryCollector.terminate(own)) } }
 func testAvailableUpdatesFollowEveryAppSortAndUnknownsStayLast() {
  func app(_ name:String,_ size:UInt64,_ age:TimeInterval?)->InstalledApp {
   var measurement=BonsaiCore.Measurement();measurement.files=size>0 ? 1:0;measurement.allocated=size
   return InstalledApp(url:root.appendingPathComponent(name+".app"),name:name,bundleID:"fixture."+name,version:"1",measurement:measurement,lastUsed:age.map {Date(timeIntervalSince1970:$0)},appStore:false,installedDate:age.map {Date(timeIntervalSince1970:$0)})
  }
  let apps=[app("App 2",200,200),app("App 10",100,100),app("Unknown",0,nil)]
  let updates=apps.reversed().map {SoftwareUpdate(id:$0.id,name:$0.name,installed:"1",available:"2",source:"Sparkle",information:"Test fixture",applicationURL:$0.url)}+[SoftwareUpdate(id:"orphan",name:"Absent",installed:"1",available:"2",source:"Homebrew cask",information:"Test fixture")]
  for field in AppSortField.allCases {
   for ascending in [true,false] {
    let order=AppSortOrder(field:field,ascending:ascending),sorted=order.sortedUpdates(updates,inventory:apps)
    XCTAssertEqual(sorted.count,4)
    if field == .name {XCTAssertEqual(sorted.map(\.name),ascending ? ["Absent","App 2","App 10","Unknown"]:["Unknown","App 10","App 2","Absent"])}
    else {XCTAssertEqual(Array(sorted.prefix(2)).map(\.name),ascending ? ["App 10","App 2"]:["App 2","App 10"]);XCTAssertEqual(Array(sorted.suffix(2)).map(\.name),["Absent","Unknown"])}
   }
  }
  let duplicate=SoftwareUpdate(id:"duplicate",name:"App 2",installed:"1",available:"2",source:"Electron",information:"Test fixture",applicationURL:apps[0].url)
  XCTAssertEqual(AppSortOrder().sortedUpdates([duplicate,updates.first {$0.name=="App 2"}!],inventory:apps).map(\.id),[apps[0].id,"duplicate"].sorted())
 }
 func fixtureApp(_ name:String="Fixture.app",identifier:String="app.fixture.example",version:String="1.0",extra:[String:Any]=[:]) throws -> InstalledApp {
  let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
  var info:[String:Any]=["CFBundleIdentifier":identifier,"CFBundleName":"Fixture","CFBundleShortVersionString":version,"CFBundleVersion":"20","CFBundlePackageType":"APPL"];info.merge(extra){_,b in b}
  try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:url.appendingPathComponent("Contents/Info.plist"));try Data(repeating:1,count:4096).write(to:url.appendingPathComponent("Contents/MacOS/fixture"))
  return InstalledApp(url:url,name:"Fixture",bundleID:identifier,version:version,measurement:try FileScanner.measure(url),lastUsed:nil,appStore:false)
 }
 func testExpandedBrowserCacheBoundaries() throws {
  _=try file("Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache/file");_=try file("Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies");_=try file("Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data")
  let rules=try CacheRules.browserCandidates(home:root);XCTAssertTrue(rules.contains { $0.relative.hasSuffix("Default/Cache") });XCTAssertFalse(rules.contains { $0.relative.hasSuffix("Cookies") || $0.relative.hasSuffix("Login Data") });XCTAssertTrue(rules.allSatisfy { $0.runningIDs==["com.brave.Browser"] })
 }
 func testBrowserSymlinkProfileOmitted() throws {
  _=try file("Library/Application Support/Google/Chrome/Default/Cache/data");let browser=root.appendingPathComponent("Library/Application Support/Google/Chrome");try FileManager.default.createSymbolicLink(at:browser.appendingPathComponent("Profile 1"),withDestinationURL:root)
  let rules=try CacheRules.browserCandidates(home:root);XCTAssertFalse(rules.contains { $0.relative.contains("Profile 1") });XCTAssertTrue(rules.contains { $0.relative.contains("Default/Cache") })
 }
 func testExpandedRulesPreserveSensitiveFolders() {
  XCTAssertTrue(CacheRules.rules.contains { $0.relative=="Library/Application Support/Codex/Cache" });XCTAssertTrue(CacheRules.rules.contains { $0.relative==".cargo/registry/cache" });XCTAssertFalse(CacheRules.rules.contains { $0.relative.contains("sessions") || $0.relative.contains("auth.json") || $0.relative.contains("workspaceStorage") });XCTAssertTrue(CacheRules.rules.filter { $0.relative.hasPrefix("Library/Application Support/Claude/") }.allSatisfy { CacheRules.electronLeaves.contains(String($0.relative.dropFirst("Library/Application Support/Claude/".count))) })
 }
 func testRemnantInstalledAndSharedNamespaceProtection() throws {
  _=try file("Library/Preferences/com.example.orphan.plist");_=try file("Library/Caches/com.example.live/cache");_=try file("Library/Caches/com.example.live.helper/cache");_=try file("Library/Application Support/com.shared/cache");_=try file("Library/Preferences/com.apple.reserved.plist")
  let report=try RemnantScanner.scan(home:root,installed:["com.example.live","com.shared.child"]);XCTAssertEqual(report.items.count,1);XCTAssertEqual(report.items.first?.absentBundleID,"com.example.orphan");XCTAssertEqual(report.items.first?.risk,"High");XCTAssertTrue(report.completeWithinCatalog)
 }
 func testRemnantAbsenceRevalidatedBeforeMutation() async throws {
  let f=try file("remnant");let reviewed=try ReviewItem(url:f,title:"Orphan",category:"Potential app leftovers",explanation:"Fixture",measurement:FileScanner.measure(f),absentBundleID:"app.fixture.absent")
  let blocked=await TrashService.perform([reviewed],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true,absenceValidator:{ _ in throw BonsaiError.changed("App reinstalled") });XCTAssertEqual(blocked.first?.status,"Skipped")
  let allowed=await TrashService.perform([reviewed],policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true,absenceValidator:{_ in });XCTAssertEqual(allowed.first?.status,"Preview");XCTAssertTrue(FileManager.default.fileExists(atPath:f.path))
 }
 func testRemnantIdentifierAndExclusion() throws {
  XCTAssertNil(RemnantScanner.identifier("Cookies"));XCTAssertNil(RemnantScanner.identifier("group.shared.vendor"));XCTAssertNil(RemnantScanner.identifier("com.apple.finder.plist"));XCTAssertEqual(RemnantScanner.identifier("com.example.app.savedState"),"com.example.app")
  let f=try file("Library/Preferences/com.example.app.plist");XCTAssertTrue(try RemnantScanner.scan(home:root,installed:[],exclusions:[f.path]).items.isEmpty)
 }
 func testInstallerAgeAndSymlinkReview() throws {
  let old=try file("old.dmg");_=try file("new.pkg");_=try file("document.txt");try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-8*86400)],ofItemAtPath:old.path);try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link.dmg"),withDestinationURL:old)
  let report=try InstallerScanner.scan(root);XCTAssertEqual(report.items.map(\.title),["old.dmg"]);XCTAssertEqual(report.items.first?.risk,"High");XCTAssertTrue(try InstallerScanner.scan(root,exclusions:[old.path]).items.isEmpty)
 }
 func testInstallerPhaseLimitsArePartialAndNonMutating() throws {
  let old=try file("Downloads/old.dmg");try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-9*86400)],ofItemAtPath:old.path)
  _=try file("Downloads/another.pkg")
  let report=try InstallerScanner.scan(old.deletingLastPathComponent(),limits:ScanLimits(nodes:1,seconds:5))
  XCTAssertFalse(report.completeWithinCatalog);XCTAssertTrue(report.items.isEmpty);XCTAssertFalse(report.issues.isEmpty)
  XCTAssertEqual(try Data(contentsOf:old).count,8192)
 }
 func testTrashAppDetectionDoesNotMutate() throws {
  let app=try fixtureApp();try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Link.app"),withDestinationURL:app.url)
  let notices=try TrashAppMonitor.inspect(root);XCTAssertEqual(notices.count,1);XCTAssertEqual(notices.first?.id,app.bundleID);XCTAssertTrue(FileManager.default.fileExists(atPath:app.url.path))
 }
 func testOrdinaryInventorySkipsDeniedBranchesWithoutFalseAbsence() throws {
  let app=try fixtureApp();let blocked=root.appendingPathComponent("service/data");try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true)
  XCTAssertEqual(chmod(blocked.path,0),0);defer {_=chmod(blocked.path,0o700)}
  let inventory=try InstalledIdentifiers.snapshot(roots:[root])
  XCTAssertTrue(inventory.identifiers.contains(app.bundleID));XCTAssertFalse(inventory.complete);XCTAssertTrue(inventory.blockedPaths.contains(blocked.path))
  XCTAssertThrowsError(try InstalledIdentifiers.read(roots:[root]))
  _=try file("Library/Preferences/com.example.orphan.plist")
  let leftovers=try CleanFlow.leftovers(home:root,roots:[root]);XCTAssertFalse(leftovers.items.isEmpty);XCTAssertFalse(leftovers.completeWithinCatalog);XCTAssertTrue(leftovers.deniedDiscoveryPaths.contains(blocked.path))
  XCTAssertTrue(leftovers.items.allSatisfy {$0.readOnlyReason == nil && $0.risk=="High" && $0.confidence.contains("incomplete")});XCTAssertTrue(CleanFlow.recommended(leftovers.items,runningIDs:[]).isEmpty)
 }
 func testOrdinaryInventoryLinksBoundsAndBrokenAppMetadata() async throws {
  let app=try fixtureApp();try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Link.app"),withDestinationURL:app.url)
  let inventory=try InstalledIdentifiers.snapshot(roots:[root]);XCTAssertTrue(inventory.complete);XCTAssertEqual(inventory.identifiers,[app.bundleID])
  let limited=try InstalledIdentifiers.snapshot(roots:[root],limits:ScanLimits(nodes:1,seconds:5));XCTAssertFalse(limited.complete)
  let malformed=root.appendingPathComponent("Broken.app");try FileManager.default.createDirectory(at:malformed,withIntermediateDirectories:true)
  XCTAssertFalse(try InstalledIdentifiers.snapshot(roots:[root]).complete)
  let worker=Task {() throws -> InstalledIdentifiers.Snapshot in try await Task.sleep(nanoseconds:50_000_000);return try InstalledIdentifiers.snapshot(roots:[root])};worker.cancel()
  do {_=try await worker.value;XCTFail("Cancelled discovery completed")} catch is CancellationError {} catch {XCTFail("Unexpected cancellation failure")}
 }
 func testGuardedCleanRowsSurviveRefreshWithoutRescanning() throws {
  let f=physicalURL(try file("Library/Caches/guarded/data"))
  let item=try ReviewItem(url:f,title:"Guarded cache",category:"Application caches",explanation:"Fixture",measurement:FileScanner.measure(f))
  let empty=CleanReport(items:[],issues:[],completeWithinCatalog:true)
  XCTAssertTrue(CleanFlow.isGuarded(item.id,exclusions:[item.id]))
  XCTAssertTrue(CleanFlow.isGuarded(item.id,exclusions:[f.deletingLastPathComponent().path]))
  XCTAssertTrue(CleanFlow.isGuarded(f.deletingLastPathComponent().path,exclusions:[item.id]))
  XCTAssertFalse(CleanFlow.isGuarded(item.id+"-other",exclusions:[item.id]))
  try FileManager.default.removeItem(at:f)
  let retained=CleanFlow.retainingGuards(empty,previous:[item],exclusions:[item.id])
  XCTAssertEqual(retained.items.map(\.id),[item.id])
  XCTAssertEqual(retained.items.first?.measurement.allocated,item.measurement.allocated)
  XCTAssertTrue(CleanFlow.retainingGuards(empty,previous:[item],exclusions:[]).items.isEmpty)
  XCTAssertEqual(CleanFlow.retainingGuards(retained,previous:[item],exclusions:[item.id]).items.count,1)
 }
 func testCleanRecommendationsAndOverlapKeepSensitiveDataUnselected() throws {
  let f=try file("Library/Caches/app.fixture/data");let m=try FileScanner.measure(f)
  func candidate(_ suffix:String,_ risk:String,_ ids:[String]=[],_ absent:String?=nil)throws->ReviewItem {try ReviewItem(url:f,title:suffix,category:"Application caches",explanation:"Fixture",risk:risk,runningIDs:ids,measurement:m,absentBundleID:absent)}
  let safe=try candidate("Safe","Review");XCTAssertEqual(CleanFlow.recommended([safe],runningIDs:[]),[safe.id])
  XCTAssertTrue(CleanFlow.recommended([try candidate("Sensitive","High")],runningIDs:[]).isEmpty)
  XCTAssertTrue(CleanFlow.recommended([try candidate("Running","Review",["app.fixture.live"])],runningIDs:["app.fixture.live"]).isEmpty)
  XCTAssertTrue(CleanFlow.recommended([try candidate("Orphan","Review",[],"com.example.orphan")],runningIDs:[]).isEmpty)
  var partial=m;partial.complete=false
  let unreadable=try ReviewItem(url:f,title:"Partial",category:"Logs",explanation:"Fixture",risk:"Low",measurement:partial)
  XCTAssertTrue(CleanFlow.recommended([unreadable],runningIDs:[]).isEmpty)
  let parent=try item(f.deletingLastPathComponent());let a=CleanReport(items:[safe],issues:[],completeWithinCatalog:true);let b=CleanReport(items:[parent],issues:["Partial fixture"],completeWithinCatalog:false,deniedDiscoveryPaths:[f.path])
  let merged=CleanFlow.merge([a,b]);XCTAssertEqual(merged.items.map(\.id),[parent.id]);XCTAssertFalse(merged.completeWithinCatalog);XCTAssertEqual(merged.accessDeniedPaths,[f.path]);XCTAssertEqual(merged.issues,["Partial fixture"])
 }
 func testUnifiedCleanIncludesOldInstallersAndVerifiedLeftovers() throws {
  _=try fixtureApp();_=try file("Library/Caches/app.fixture.cache/data")
  _=try file("Library/Preferences/com.example.orphan.plist")
  let old=try file("Downloads/old.dmg");try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-9*86400)],ofItemAtPath:old.path)
  _=try file("Downloads/new.pkg")
  let temp=root.appendingPathComponent("temporary");try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  let report=try CleanFlow.scan(home:root,roots:[root],temporaryRoot:temp)
  XCTAssertTrue(report.items.contains {$0.id==physicalURL(old).path},"Missing installer "+old.path+": "+report.issues.joined(separator:"; ")+" items="+report.items.map(\.id).joined(separator:","))
  XCTAssertTrue(report.items.contains {$0.absentBundleID=="com.example.orphan"},"Missing orphan: "+report.issues.joined(separator:"; ")+" items="+report.items.map(\.id).joined(separator:","))
  XCTAssertFalse(report.items.contains {$0.title=="new.pkg"})
  XCTAssertTrue(CleanFlow.recommended(report.items,runningIDs:[]).isDisjoint(with:Set(report.items.filter {$0.absentBundleID != nil || $0.category=="Old installers"}.map(\.id))))
  XCTAssertEqual(CleanFlow.category("Communication"),"App Caches");XCTAssertEqual(CleanFlow.category("Cloud clients"),"Cloud Storage")
 }
 func testFastInstalledIdentifierInventory() throws {
  let a=try fixtureApp();_=try fixtureApp("Other.app",identifier:"app.fixture.other");let ids=try InstalledIdentifiers.read(roots:[root]);XCTAssertTrue(ids.contains(a.bundleID));XCTAssertTrue(ids.contains("app.fixture.other"));XCTAssertTrue(InstalledIdentifiers.claims("app.fixture",installed:ids))
 }
 func testAppcastHumanVersionAndCompatibility() throws {
  let app=try fixtureApp();let data=Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>Future</title><sparkle:minimumSystemVersion>100.0</sparkle:minimumSystemVersion><enclosure sparkle:shortVersionString="3.0" sparkle:version="300" /></item><item><title>Release</title><sparkle:releaseNotesLink>https://example.com/notes</sparkle:releaseNotesLink><enclosure sparkle:shortVersionString="1.2" sparkle:version="21" /></item></channel></rss>"#.utf8)
  let update=try AppcastMetadata.update(app:app,data:data,feed:URL(string:"https://example.com/feed")!,systemVersion:"14.0");XCTAssertEqual(update?.available,"1.2");XCTAssertEqual(update?.source,"Sparkle");XCTAssertEqual(update?.canInstall,SoftwareUpdate.sparkleInstallationAvailable);XCTAssertEqual(update?.releaseNotesURL?.host,"example.com")
 }
 func testAppcastBuildOnlyAndMalformedSafety() throws {
  let app=try fixtureApp();let data=Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure sparkle:version="21" /></item></channel></rss>"#.utf8)
  XCTAssertEqual(try AppcastMetadata.update(app:app,data:data,feed:URL(string:"https://example.com/feed")!,systemVersion:"14.0")?.available,"Build 21");XCTAssertThrowsError(try AppcastMetadata.parse(Data("<broken>".utf8)));XCTAssertThrowsError(try AppcastMetadata.parse(Data("<!DOCTYPE rss SYSTEM 'file:///etc/passwd'><rss/>".utf8)))
 }
 func testAppcastChannelAndPlatformFiltering() throws {
  let data=Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:channel>beta</sparkle:channel><enclosure sparkle:version="30"/></item><item><enclosure sparkle:version="40" sparkle:os="windows"/></item><item><enclosure sparkle:version="20"/></item></channel></rss>"#.utf8);XCTAssertEqual(try AppcastMetadata.parse(data).count,1);XCTAssertEqual(try AppcastMetadata.parse(data).first?.build,"20")
 }
 func testVersionComparisonAvoidsAmbiguousVersions() {
  XCTAssertTrue(VersionOrder.newer("1.10",than:"1.9"));XCTAssertTrue(VersionOrder.newer("v2.0",than:"1.9"));XCTAssertFalse(VersionOrder.newer("Unknown",than:"1"));XCTAssertFalse(VersionOrder.newer("2.0-beta",than:"1.0"));XCTAssertFalse(VersionOrder.newer("1.0",than:"1.0"))
 }
 func testAppStoreExactMacIdentity() throws {
  let app=try fixtureApp();let data=Data(#"{"results":[{"bundleId":"app.fixture.other","kind":"mac-software","version":"4.0"},{"bundleId":"app.fixture.example","kind":"software","version":"9.0"},{"bundleId":"app.fixture.example","kind":"mac-software","version":"1.5","trackViewUrl":"https://apps.apple.com/app/id123","releaseNotes":"Release notes"}]}"#.utf8)
  let update=try AppStoreMetadata.parse(data,app:app);XCTAssertEqual(update?.available,"1.5");XCTAssertEqual(update?.information,"Release notes");XCTAssertTrue(update?.canInstall ?? false)
 }
 func testMetadataConsentAndURLBoundaries() async {
  do { _=try await UpdateDiscovery.check([],consent:false);XCTFail() } catch { XCTAssertTrue(error is BonsaiError) }
  do { _=try await PublicMetadataHTTP.get(URL(string:"https://example.com/feed")!,consent:false);XCTFail() } catch { XCTAssertTrue(error is BonsaiError) }
  XCTAssertFalse(PublicMetadataHTTP.valid(URL(string:"https://127.0.0.1/feed")!));XCTAssertFalse(PublicMetadataHTTP.valid(URL(string:"https://user:pass@example.com/feed")!));XCTAssertFalse(PublicMetadataHTTP.valid(URL(string:"http://example.com/feed")!));XCTAssertFalse(PublicMetadataHTTP.valid(URL(string:"https://service.local/feed")!));XCTAssertTrue(PublicMetadataHTTP.valid(URL(string:"https://example.com/feed")!))
 }
 func testMetadataFetchFailureIsItemized() async throws {
  let app=try fixtureApp(extra:["SUFeedURL":"https://example.com/feed"]);let report=try await UpdateDiscovery.check([app],consent:true,fetch:{ _ in throw BonsaiError.unavailable("Offline fixture") });XCTAssertEqual(report.checked,1);XCTAssertTrue(report.updates.isEmpty);XCTAssertTrue(report.notes.contains { $0.contains("Offline fixture") })
 }
 func testNativeUpdateHandoffCannotLaunchBrew() async {
  let update=SoftwareUpdate(id:"unsafe;token",name:"Fixture",installed:"1",available:"2",source:"Appcast",information:"Fixture");let result=await UpdateService.install(update,consent:true);XCTAssertEqual(result.status,"Unavailable")
 }
 func testIncompleteHealthIsLabeled() {
  var snapshot=TelemetrySnapshot();XCTAssertEqual(snapshot.health,"Metrics incomplete");snapshot.memoryTotal=100;snapshot.diskTotal=100;snapshot.diskFree=50;snapshot.pressure="Normal";snapshot.thermal="Nominal";XCTAssertEqual(snapshot.health,"No pressure detected");snapshot.pressure="Warning";XCTAssertEqual(snapshot.health,"Memory under pressure")
 }
 func testRunningApplicationFamilyBoundaries() {
  XCTAssertTrue(ApplicationActivity.isRunning(["com.adobe.*"],among:["com.adobe.Photoshop"]))
  XCTAssertFalse(ApplicationActivity.isRunning(["com.adobe.*"],among:["com.adobeevil.Photoshop"]))
  XCTAssertFalse(ApplicationActivity.isRunning(CleanCatalog.classify("Claude").1,among:["com.todesktop.230313mzl4w4u92"]))
  XCTAssertTrue(ApplicationActivity.isRunning(CleanCatalog.classify("net.imput.helium").1,among:["net.imput.helium"]))
 }
 func testDiscoveryBudgetsAreLabeledPartial() throws {
  _=try fixtureApp();let inventory=try AppInventory.inspect(roots:[root],limits:ScanLimits(nodes:0,seconds:2));XCTAssertFalse(inventory.complete);XCTAssertTrue(inventory.issues.contains { $0.contains("budget") })
  let report=try CleanCatalog.dependencyReport(in:root,limits:ScanLimits(nodes:0,seconds:2));XCTAssertFalse(report.completeWithinCatalog);XCTAssertTrue(report.issues.contains { $0.contains("budget") })
 }
 func testAppcastMaximumSystemAndHardware() throws {
  let app=try fixtureApp();let xml=Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>200</sparkle:version><sparkle:maximumSystemVersion>13.0</sparkle:maximumSystemVersion></item><item><sparkle:version>300</sparkle:version><sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements></item></channel></rss>"#.utf8)
  XCTAssertNil(try AppcastMetadata.update(app:app,data:xml,feed:URL(string:"https://example.com/feed")!,systemVersion:"14.0"));XCTAssertFalse(VersionOrder.newer("1.0.0",than:"1.0"));XCTAssertTrue(VersionOrder.newer("1.0.1",than:"1"))
 }
 func testUnsupportedBrewResponseDoesNotMeanNoUpdates() {
  XCTAssertThrowsError(try UpdateService.parseBrew(Data("{}".utf8)));XCTAssertThrowsError(try UpdateService.parseBrew(Data("{\"casks\":null}".utf8)))
 }
 func testCatalogCanonicalExclusionsAndOverlap() throws {
  let blocked=try file("Library/Caches/com.fixture.app/data");_=try file("Library/Application Support/Slack/Cache/data");let tmp=root.appendingPathComponent("empty-temp");try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true)
  let report=try CleanCatalog.scan(home:root,exclusions:[blocked.deletingLastPathComponent().path],temporaryRoot:tmp)
  XCTAssertFalse(report.items.contains { $0.title=="com.fixture.app" });XCTAssertEqual(report.items.filter { $0.id.contains("Slack/Cache") }.count,1)
 }
 func testCompatibilityStorageStaysProtected() throws {
  let home=FileManager.default.homeDirectoryForCurrentUser
  let policy=PathPolicy.standard
  for name in AppIdentity.protectedFolderNames {
   let history=home.appendingPathComponent("Library/Application Support/"+name+"/history.json")
   XCTAssertTrue(policy.protected.contains { within(history.path,$0.path) })
   _=try file("Library/Caches/"+name+"/fixture")
  }
  XCTAssertNil(RemnantScanner.identifier(AppIdentity.bundleIdentifier+".plist"))
  for prefix in AppIdentity.protectedNamePrefixes { XCTAssertNil(RemnantScanner.identifier(prefix+"mac.plist")) }
  _=try file("Library/Caches/com.fixture.review/cache")
  let tmp=root.appendingPathComponent("empty-temp");try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true)
  let report=try CleanCatalog.scan(home:root,temporaryRoot:tmp)
  for name in AppIdentity.protectedFolderNames {XCTAssertFalse(report.items.contains {$0.url.lastPathComponent==name})}
  XCTAssertTrue(report.items.contains { $0.url.lastPathComponent=="com.fixture.review" })
 }
 func testApplicationSortingDirectionsUnknownsAndTies() {
  func app(_ name:String,_ size:UInt64,_ date:TimeInterval?,known:Bool=true)->InstalledApp { var m=BonsaiCore.Measurement();m.allocated=size;m.files=known ? 1 : 0;return InstalledApp(url:root.appendingPathComponent(name+".app"),name:name,bundleID:"test."+name,version:"1",measurement:m,lastUsed:date.map { Date(timeIntervalSince1970:$0) },appStore:false,installedDate:date.map { Date(timeIntervalSince1970:$0) }) }
  let a=app("App 2",20,20),b=app("App 10",10,10),c=app("Unknown",0,nil,known:false),d=app("App 3",20,20);let input=[c,b,d,a]
  XCTAssertEqual(AppSortOrder().sorted(input).map(\.name),["App 2","App 3","App 10","Unknown"])
  XCTAssertEqual(AppSortOrder(field:.name,ascending:false).sorted(input).map(\.name),["Unknown","App 10","App 3","App 2"])
  for field in [AppSortField.size,.lastUsed,.installed] {
   XCTAssertEqual(AppSortOrder(field:field,ascending:true).sorted(input).map(\.name),["App 10","App 2","App 3","Unknown"])
   XCTAssertEqual(AppSortOrder(field:field,ascending:false).sorted(input).map(\.name),["App 2","App 3","App 10","Unknown"])
  }
  var order=AppSortOrder();order.choose(.name);XCTAssertFalse(order.ascending);order.choose(.size);XCTAssertFalse(order.ascending);order.choose(.size);XCTAssertTrue(order.ascending);order.choose(.name);XCTAssertTrue(order.ascending)
 }
 func testInventoryDeduplicatesOverlappingRoots() throws {
  let app=try fixtureApp();let values=try AppInventory.scan(roots:[app.url,root,app.url]);XCTAssertEqual(values.count,1);XCTAssertNotNil(values[0].installedDate)
 }
 func association(_ app:InstalledApp,inventory:[InstalledApp]?=nil,limits:ScanLimits=ScanLimits()) throws -> AppAssociationReport {
  try AppInventory.associationReport(app,inventory:inventory ?? [app],home:root,temporaryCacheRoot:root.appendingPathComponent("temporary"),systemLibrary:root.appendingPathComponent("system"),policy:PathPolicy(roots:[root],protected:[root.appendingPathComponent("system")]),limits:limits)
 }
 func testAssociationGroupsDefaultsAndRetainedChoices() throws {
  let app=try fixtureApp();_=try file("Library/Caches/\(app.bundleID)/data");_=try file("temporary/\(app.bundleID)/data");_=try file("Library/Preferences/\(app.bundleID).plist");_=try file("Library/Application Support/Fixture/documents");_=try file("Library/Caches/\(app.bundleID).other/data")
  let report=try association(app);XCTAssertEqual(report.files.count,5);XCTAssertFalse(report.files.contains { $0.id.contains(".other") });XCTAssertTrue(report.files.allSatisfy(\.selectable))
  var plan=AppRemovalPlan(report:report,selectDefaults:true);XCTAssertEqual(plan.items.count,3);XCTAssertFalse(plan.items.contains { $0.category=="Associated data" && $0.title=="Preferences" });XCTAssertGreaterThan(plan.appBytes,0);XCTAssertGreaterThan(plan.dataBytes,0)
  let prefs=report.files.first { $0.kind == .preferences }!;plan.set(prefs.id,selected:true);XCTAssertEqual(plan.items.count,4);plan.setReviewGroup(true);XCTAssertEqual(plan.items.count,5)
  let support=report.files.first { $0.kind == .support }!;XCTAssertEqual(support.item.confidence,"App name match; manual review");plan.set(support.id,selected:false)
  let refreshed=AppRemovalPlan(report:report,selectDefaults:true,retaining:plan.selected);XCTAssertFalse(refreshed.selected.contains(support.id));XCTAssertEqual(refreshed.items.count,4)
  let missing=AppAssociationReport(appID:app.id,files:report.files.filter { $0.id != prefs.id });XCTAssertFalse(AppRemovalPlan(report:missing,retaining:plan.selected).selected.contains(prefs.id))
  plan.clear();XCTAssertTrue(plan.items.isEmpty);XCTAssertEqual(plan.appBytes,0);XCTAssertEqual(plan.dataBytes,0)
 }
 func testDeclaredHelpersBlockedAndNotInferredByPrefix() throws {
  let app=try fixtureApp(extra:["SMPrivilegedExecutables":["app.fixture.helper":"identifier app.fixture.helper"]]);_=try file("system/PrivilegedHelperTools/app.fixture.helper");_=try file("system/PrivilegedHelperTools/app.fixture.example.unknown");_=try file("system/LaunchDaemons/app.fixture.helper.plist")
  let report=try association(app);XCTAssertEqual(report.files.filter { $0.kind == .helper }.count,1);XCTAssertFalse(report.files.contains { $0.id.contains("unknown") });let blocked=report.files.filter { !$0.selectable };XCTAssertEqual(blocked.count,2)
  var plan=AppRemovalPlan(report:report,selectDefaults:true);plan.setReviewGroup(true);for file in blocked { plan.set(file.id,selected:true) };XCTAssertEqual(plan.items.count,1)
 }
 func testAmbiguousAppNameSupportRetained() throws {
  let app=try fixtureApp();let other=try fixtureApp("Other.app",identifier:"app.fixture.other");_=try file("Library/Application Support/Fixture/document")
  XCTAssertFalse(try association(app,inventory:[app,other]).files.contains { $0.kind == .support })
  let google=try fixtureApp("Google.app",identifier:"app.fixture.google",extra:["CFBundleName":"Google"]);let named=InstalledApp(url:google.url,name:"Google",bundleID:google.bundleID,version:"1",measurement:google.measurement,lastUsed:nil,appStore:false);_=try file("Library/Application Support/Google/document")
  XCTAssertFalse(try association(named).files.contains { $0.kind == .support })
 }
 func testAssociationSymlinkPermissionsAndBudgetUnavailable() throws {
  let app=try fixtureApp();let cache=root.appendingPathComponent("Library/Caches/"+app.bundleID);try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.createSymbolicLink(at:cache,withDestinationURL:app.url)
  let report=try association(app);XCTAssertFalse(report.files.first { $0.kind == .cache }!.selectable)
  let limited=try association(app,limits:ScanLimits(nodes:1,seconds:5));XCTAssertFalse(limited.files.first!.selectable);XCTAssertFalse(limited.issues.isEmpty);XCTAssertTrue(AppRemovalPlan(report:limited,selectDefaults:true).items.isEmpty)
  try FileManager.default.removeItem(at:cache);_=try file("Library/Caches/\(app.bundleID)/data");try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:cache.path);defer { try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:cache.path) };XCTAssertFalse(try association(app).files.first { $0.kind == .cache }!.selectable)
 }
 func testAssociationCancellationAndReviewPreviewSelection() async throws {
  let app=try fixtureApp();_=try file("Library/Caches/\(app.bundleID)/data");_=try file("Library/Application Support/Fixture/document")
  let task=Task { try Task.checkCancellation();return try self.association(app) };task.cancel();do { _=try await task.value;XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
  let report=try association(app);let plan=AppRemovalPlan(report:report,selectDefaults:true);let outcomes=await TrashService.perform(plan.items,policy:PathPolicy(roots:[root]),runningIDs:{[]},dryRun:true);XCTAssertEqual(outcomes.map(\.status),["Preview","Preview"]);XCTAssertFalse(outcomes.contains { $0.path.contains("Application Support") });XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("Library/Application Support/Fixture/document").path))
 }
 func testPerUserCacheCapabilityAndBoundaries() throws {
  if let cache=UserCacheLocation.url { XCTAssertTrue(PathPolicy.standard.roots.contains(cache));XCTAssertThrowsError(try PathPolicy.standard.validate(cache));XCTAssertFalse(PathPolicy.standard.roots.contains(cache.deletingLastPathComponent())) } else { XCTAssertFalse(PathPolicy.standard.roots.contains(URL(fileURLWithPath:"/private/var/folders"))) }
 }

 func testAppRemovalAndOutstandingReviewTotals() throws {
  let app=try fixtureApp();_=try file("Library/Caches/\(app.bundleID)/data");_=try file("Library/Preferences/\(app.bundleID).plist");_=try file("Library/Application Support/Fixture/document")
  let report=try association(app);let cache=report.files.first { $0.kind == .cache }!,prefs=report.files.first { $0.kind == .preferences }!,support=report.files.first { $0.kind == .support }!
  let blocked=AppAssociatedFile(item:support.item,kind:.support,blockedReason:"Permission unavailable")
  let filtered=AppAssociationReport(appID:app.id,files:report.files.filter { $0.id != support.id }+[blocked])
  var plan=AppRemovalPlan(report:filtered,selectDefaults:true)
  XCTAssertEqual(plan.removalBytes,app.measurement.allocated+cache.item.measurement.allocated)
  XCTAssertEqual(plan.reviewBytes,prefs.item.measurement.allocated)
  let total=plan.removalBytes+plan.reviewBytes;plan.set(prefs.id,selected:true)
  XCTAssertEqual(plan.removalBytes,total);XCTAssertEqual(plan.reviewBytes,0)
  plan.set(prefs.id,selected:false);XCTAssertEqual(plan.reviewBytes,prefs.item.measurement.allocated)
  plan.clear();XCTAssertEqual(plan.removalBytes,0);XCTAssertEqual(plan.reviewBytes,prefs.item.measurement.allocated)
  plan.setReviewGroup(true);XCTAssertEqual(plan.removalBytes,prefs.item.measurement.allocated);XCTAssertEqual(plan.reviewBytes,0);XCTAssertFalse(plan.selected.contains(support.id))
 }

 func testMetadataFirstSizingAndIdentityRevalidation() async throws {
  let app=try fixtureApp();let metadata=try AppInventory.scan(roots:[app.url],measureSizes:false)
  XCTAssertEqual(metadata.count,1);XCTAssertEqual(metadata[0].measurement.files,0)
  let trace=MaintenanceFixtureTrace()
  let finished=try await AppSizePipeline.run(metadata,progress:{app,_ in await trace.add(app.name)})
  XCTAssertEqual(finished,1);let names=await trace.values();XCTAssertEqual(names,[app.name])
  let measured=try AppSizePipeline.measure(metadata[0]);XCTAssertGreaterThan(measured.measurement.allocated,0)
  let moved=root.appendingPathComponent("original-bundle");try FileManager.default.moveItem(at:app.url,to:moved)
  try FileManager.default.createDirectory(at:app.url,withIntermediateDirectories:true)
  XCTAssertThrowsError(try AppSizePipeline.measure(metadata[0]))
 }
 func testSizingTwoWorkersBudgetAndCancellation() async throws {
  let app=try fixtureApp();let apps=(0..<5).map {i in InstalledApp(url:app.url,name:"Fixture \(i)",bundleID:app.bundleID,version:"1",measurement:app.measurement,lastUsed:nil,appStore:false)}
  let probe=SizeFixtureProbe()
  let count=try await AppSizePipeline.run(apps,measure:{app in probe.enter();defer {probe.leave()};Thread.sleep(forTimeInterval:0.03);return app})
  XCTAssertEqual(count,5);XCTAssertEqual(probe.maximum,2)
  let none=try await AppSizePipeline.run(apps,seconds:0,measure:{_ in XCTFail("Expired budget started sizing");return app})
  XCTAssertEqual(none,0)
  let trace=MaintenanceFixtureTrace()
  let task=Task {try await AppSizePipeline.run(apps,progress:{app,_ in await trace.add(app.name);withUnsafeCurrentTask {$0?.cancel()}},measure:{app in Thread.sleep(forTimeInterval:0.02);return app})}
  do {_=try await task.value;XCTFail("Cancelled sizing completed")} catch {XCTAssertTrue(error is CancellationError)}
  let published=await trace.values();XCTAssertEqual(published.count,1)
 }
 func testUninstallProgressCancelPreservesRemainingAndRecovery() async throws {
  let urls=try [file("first"),file("second"),file("third")];let items=try urls.map {try item($0)}
  let bin=root.appendingPathComponent("disposable-bin");try FileManager.default.createDirectory(at:bin,withIntermediateDirectories:true)
  let trace=MaintenanceFixtureTrace()
  let worker=Task {await TrashService.perform(items,policy:PathPolicy(roots:[self.root]),runningIDs:{[]},mover:{url in let dst=bin.appendingPathComponent(url.lastPathComponent);try FileManager.default.moveItem(at:url,to:dst);return dst},progress:{i,_,outcomes in await trace.add("\(i):\(outcomes.count)");if i==1 {withUnsafeCurrentTask {$0?.cancel()}}})}
  let outcomes=await worker.value
  XCTAssertEqual(outcomes.map(\.status),["Trashed","Cancelled","Cancelled"])
  let events=await trace.values();XCTAssertEqual(events,["0:0","1:1","2:2"])
  XCTAssertFalse(FileManager.default.fileExists(atPath:urls[0].path));XCTAssertTrue(FileManager.default.fileExists(atPath:outcomes[0].recovery!))
  XCTAssertTrue(FileManager.default.fileExists(atPath:urls[1].path));XCTAssertTrue(FileManager.default.fileExists(atPath:urls[2].path))
 }
 func testLogsDiscoveryAndPartialUninstallSummary() throws {
  let app=try fixtureApp();_=try file("Library/Logs/\(app.bundleID)/diagnostic");_=try file("Library/Preferences/\(app.bundleID).plist")
  let report=try association(app);let plan=AppRemovalPlan(report:report,selectDefaults:true)
  let log=report.files.first {$0.kind == .logs}!,prefs=report.files.first {$0.kind == .preferences}!
  XCTAssertTrue(plan.selected.contains(log.id));XCTAssertFalse(plan.selected.contains(prefs.id))
  let group=UninstallGroup(app:app,plan:plan)
  let outcomes=[ItemOutcome(title:"App",path:app.id,status:"Trashed",detail:"",recovery:"fixture-bin"),ItemOutcome(title:"Log",path:log.id,status:"Cancelled",detail:"")]
  let summary=UninstallSummary(groups:[group],outcomes:outcomes)
  XCTAssertEqual(summary.removedApps,1);XCTAssertEqual(summary.removedData,0);XCTAssertEqual(summary.cancelled,1);XCTAssertEqual(summary.failed,0)
  XCTAssertEqual(summary.movedBytes,report.files.first {$0.kind == .application}!.item.measurement.allocated)
  XCTAssertEqual(summary.headline,"Removal partly completed")
  let dataOnly=UninstallSummary(groups:[group],outcomes:[ItemOutcome(title:"Logs",path:log.id,status:"Trashed",detail:"")])
  XCTAssertEqual(dataOnly.removedApps,0);XCTAssertEqual(dataOnly.headline,"Selected app files removed")
  XCTAssertEqual(dataOnly.movedBytes,log.item.measurement.allocated)
 }

 func testRevisionAndBuildVersionOrdering() throws {
  XCTAssertTrue(VersionOrder.newer("v2.1.5-1",than:"2.1.2-1"))
  XCTAssertFalse(VersionOrder.newer("2.1.2-1",than:"v2.1.5-1"))
  XCTAssertTrue(VersionOrder.newer("Build 4216",than:"Build 4215"))
  XCTAssertFalse(VersionOrder.newer("2.0-beta",than:"1.0"))
  let app=try fixtureApp(version:"1.0")
  let xml=Data("<rss><channel><item><enclosure sparkle:version='21' sparkle:shortVersionString='1.0'/></item></channel></rss>".utf8)
  XCTAssertNotNil(try AppcastMetadata.update(app:app,data:xml,feed:URL(string:"https://example.com/feed.xml")!,systemVersion:"14.0"))
 }
 func testElectronDeclaredSourcesAndRefusal() throws {
  let generic=Data("provider: generic\nurl: 'https://example.com/releases'\n".utf8)
  XCTAssertEqual(ElectronMetadata.manifestURL(configuration:generic)?.absoluteString,"https://example.com/releases/latest-mac.yml")
  let github=Data("provider: github\nowner: fixture\nrepo: app\nprivate: false\n".utf8)
  XCTAssertEqual(ElectronMetadata.manifestURL(configuration:github)?.absoluteString,"https://github.com/fixture/app/releases/latest/download/latest-mac.yml")
  XCTAssertNil(ElectronMetadata.manifestURL(configuration:Data("provider: github\nowner: ../private\nrepo: app\n".utf8)))
  XCTAssertNil(ElectronMetadata.manifestURL(configuration:Data("provider: generic\nurl: http://127.0.0.1/releases\n".utf8)))
  XCTAssertNil(ElectronMetadata.manifestURL(configuration:Data("provider: github\nowner: fixture\nrepo: app\nprivate: true\n".utf8)))
  let app=try fixtureApp()
  let update=try ElectronMetadata.update(app:app,data:Data("version: 1.2.0\nfiles:\n  - url: unused.zip\n".utf8),source:URL(string:"https://example.com/latest-mac.yml")!)
  XCTAssertEqual(update?.available,"1.2.0");XCTAssertEqual(update?.applicationURL,app.url)
  XCTAssertNil(try ElectronMetadata.update(app:app,data:Data("version: 1.0\n".utf8),source:URL(string:"https://example.com/latest-mac.yml")!))
  XCTAssertThrowsError(try ElectronMetadata.update(app:app,data:Data(repeating:42,count:65_537),source:URL(string:"https://example.com/latest-mac.yml")!))
 }
 func testBrewInstalledAppMatchingAndSourceDeduplication() throws {
  let app=try fixtureApp()
  func data(_ version:String,_ token:String="fixture")->Data {Data("{\"casks\":[{\"token\":\"\(token)\",\"version\":\"\(version)\",\"installed\":\"1.0\",\"artifacts\":[{\"app\":[\"Fixture.app\"]}]}]}".utf8)}
  let updates=try BrewCatalog.updates(data("1.1"),apps:[app]);XCTAssertEqual(updates.count,1);XCTAssertEqual(updates[0].name,app.name);XCTAssertEqual(updates[0].applicationURL,app.url)
  XCTAssertTrue(try BrewCatalog.updates(data("1.0"),apps:[app]).isEmpty)
  XCTAssertTrue(try BrewCatalog.updates(data("1.1"),apps:[]).isEmpty)
  XCTAssertTrue(try BrewCatalog.updates(data("1.1","../../bad"),apps:[app]).isEmpty)
  let other=InstalledApp(url:root.appendingPathComponent("Other/Fixture.app"),name:"Other",bundleID:"app.other",version:"1",measurement:Measurement(),lastUsed:nil,appStore:false)
  XCTAssertTrue(try BrewCatalog.updates(data("1.1"),apps:[app,other]).isEmpty)
  let publisher=SoftwareUpdate(id:"feed:fixture",name:app.name,installed:"1",available:"2",source:"Appcast",information:"Fixture",applicationURL:app.url)
  XCTAssertEqual(BrewCatalog.merge(updates+[publisher]).map(\.id),[publisher.id])
  XCTAssertEqual(BrewCatalog.merge(updates+[publisher],preferInstallable:true).map(\.id),[SoftwareUpdate.sparkleInstallationAvailable ? publisher.id : updates[0].id])
 }
 func testTapMetadataIsLiteralBoundedAndNeverExecuted() throws {
  let text="cask \"fixture\" do\n  version \"1.1\"\n  homepage \"https://example.com/releases\"\nend"
  let release=BrewCatalog.literalRelease(text);XCTAssertEqual(release?.version,"1.1");XCTAssertEqual(release?.homepage?.host,"example.com")
  XCTAssertNil(BrewCatalog.literalRelease("cask \"fixture\" do\n version \"#{run_code()}\""))
  let tapFile=try file("Taps/vendor/homebrew-tools/Casks/fixture.rb");try Data(text.utf8).write(to:tapFile)
  XCTAssertEqual(BrewCatalog.localTapReleases(root:root.appendingPathComponent("Taps"))["fixture"]?.version,"1.1")
  let app=try fixtureApp()
  let data=Data("{\"casks\":[{\"token\":\"fixture\",\"version\":\"1.0\",\"installed\":\"1.0\",\"artifacts\":[{\"app\":[\"Fixture.app\"]}]}]}".utf8)
  let update=try BrewCatalog.updates(data,apps:[app],taps:["fixture":release!]).first
  XCTAssertEqual(update?.available,"1.1");XCTAssertEqual(update?.source,"Homebrew tap");XCTAssertFalse(update?.canInstall ?? true)
 }

 func testAppleCatalogUniversalMacApps() throws {
  let app=try fixtureApp(identifier:"com.apple.TestFlight",version:"4.3.0")
  let json=Data("{\"results\":[{\"bundleId\":\"com.apple.TestFlight\",\"kind\":\"software\",\"version\":\"4.4.0\"}]}".utf8)
  XCTAssertEqual(try AppStoreMetadata.parse(json,app:app)?.available,"4.4.0")
  let wrong=Data("{\"results\":[{\"bundleId\":\"app.unrelated\",\"kind\":\"software\",\"version\":\"4.4.0\"}]}".utf8)
  XCTAssertNil(try AppStoreMetadata.parse(wrong,app:app))
 }

 func testLoginInventorySnapshotOwnershipAndRoundtrip() throws {
  let entry=LoginEntry(id:"fixture",name:"Fixture",identifier:"app.fixture",owner:getuid(),url:root,kind:"App",enabled:true,details:"Enabled",section:"Login items")
  let snapshot=LoginInventorySnapshot(entries:[entry],date:Date(timeIntervalSince1970:1234))
  let decoded=try JSONDecoder().decode(LoginInventorySnapshot.self,from:JSONEncoder().encode(snapshot))
  XCTAssertEqual(decoded.date,snapshot.date);XCTAssertEqual(decoded.currentUser().map(\.id),[entry.id]);XCTAssertTrue(decoded.currentUser(getuid()+1).isEmpty)
 }
 func testUpdateInventoryBeyondTenStoreAppsAndBoundedConcurrency() async throws {
  let apps=(0..<14).map {i in InstalledApp(url:root.appendingPathComponent("App\(i).app"),name:"App\(i)",bundleID:"app.fixture.\(i)",version:"1",measurement:Measurement(),lastUsed:nil,appStore:true)}
  let probe=UpdateFixtureProbe()
  let result=try await UpdateDiscovery.check(apps,consent:true,fetch:{url in
   await probe.enter();try await Task.sleep(nanoseconds:10_000_000);await probe.leave()
   let id=URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.first {$0.name=="bundleId"}!.value!
   return Data("{\"results\":[{\"bundleId\":\"\(id)\",\"kind\":\"mac-software\",\"version\":\"2\"}]}".utf8)
  })
  XCTAssertEqual(result.checked,14);XCTAssertEqual(result.updates.count,14);XCTAssertEqual(result.appStates?.count,14)
  let maximum=await probe.maximum();XCTAssertEqual(maximum,3)
 }

}

actor MaintenanceFixtureTrace {
 private var entries:[String]=[]
 func add(_ entry:String) {entries.append(entry)}
 func values()->[String] {entries}
}

final class SizeFixtureProbe:@unchecked Sendable {
 private let lock=NSLock();private var active=0;private var peak=0
 func enter() {lock.lock();active+=1;peak=max(peak,active);lock.unlock()}
 func leave() {lock.lock();active-=1;lock.unlock()}
 var maximum:Int {lock.lock();defer {lock.unlock()};return peak}
}

private actor StartupFixtureExecutor {
 private var disabled=false;private var trace:[[String]]=[]
 func calls()->[[String]] {trace}
 func run(_ path:String,_ args:[String])->CommandResult {
  guard path=="/bin/launchctl" else {return CommandResult(status:1)}
  trace.append(args)
  switch args.first {case "disable":disabled=true;case "enable":disabled=false;default:break}
  return CommandResult(status:0,output:"disabled services = { \"app.bonsai.fixture\" => \(disabled ? "true" : "false") }")
 }
}

private actor UpdateFixtureProbe {
 private var active=0;private var peak=0
 func enter() {active+=1;peak=max(peak,active)}
 func leave() {active-=1}
 func maximum()->Int {peak}
}

private final class CleanActivityFixture:@unchecked Sendable {
 private let lock=NSLock();private var values:[CleanScanActivity]=[]
 func append(_ value:CleanScanActivity) {lock.lock();values.append(value);lock.unlock()}
 var samples:[CleanScanActivity] {lock.lock();defer {lock.unlock()};return values}
}

extension CoreTests {
 func testMaintenanceBackendStructuredOutcomesRejectMissingAndDuplicateRecords() {
  for (value,status) in [("applied","Completed"),("unchanged","Unchanged"),("skipped","Skipped"),("unavailable","Unavailable"),("attention","Needs attention"),("failed","Failed")] {
   let output="Work output\nBONSAI_TASK_RESULT\tcache_refresh\t"+value+"\n"
   let result=MaintenanceBackend.parse(CommandResult(status:0,output:output,standardOutput:output),action:"cache_refresh",title:"Finder",path:"fixture")
   XCTAssertEqual(result.status,status);XCTAssertFalse(result.detail.contains("BONSAI_TASK_RESULT"))
  }
  for output in ["", "BONSAI_TASK_RESULT\tother\tapplied", "BONSAI_TASK_RESULT\tcache_refresh\tapplied\nBONSAI_TASK_RESULT\tcache_refresh\tapplied", "BONSAI_TASK_RESULT\tcache_refresh\tbogus"] {
   XCTAssertEqual(MaintenanceBackend.parse(CommandResult(status:0,output:output,standardOutput:output),action:"cache_refresh",title:"Finder",path:"fixture").status,"Verification failed")
  }
  XCTAssertEqual(MaintenanceBackend.parse(CommandResult(status:0,timedOut:true),action:"cache_refresh",title:"Finder",path:"fixture").status,"Failed")
 }
 func testMaintenanceUnchangedAndUnavailableAreNotCountedAsChanges() {
  let items=[ItemOutcome(title:"Already healthy",path:"a",status:"Unchanged",detail:""),ItemOutcome(title:"Not available",path:"b",status:"Unavailable",detail:"")]
  let summary=MaintenanceSummary(tasks:[],outcomes:items)
  XCTAssertEqual(summary.refreshed,0);XCTAssertEqual(summary.attention,0);XCTAssertEqual(summary.unchanged,1);XCTAssertEqual(summary.unavailable,1)
 }
 func testMaintenanceTrashBoundariesAndRecovery() throws {
  let home=root.appendingPathComponent("home")
  let cache=try file("home/Library/Caches/com.apple.iconservices.store")
  let recovery=root.appendingPathComponent("retired-cache")
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(cache,home:home,mover:{_ in recovery}))
  XCTAssertEqual(try MaintenanceCacheTrash.move(cache,home:home,mover:{url in try FileManager.default.moveItem(at:url,to:recovery);return recovery}),recovery)
  try FileManager.default.moveItem(at:recovery,to:cache)
  let other=try file("home/Library/Caches/other")
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(other,home:home,mover:{_ in XCTFail("Wrong path must not move");return nil}))
  let linked=home.appendingPathComponent("Library/Caches/com.apple.iconservices")
  try FileManager.default.createSymbolicLink(at:linked,withDestinationURL:cache)
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(linked,home:home,mover:{_ in XCTFail("Link must not move");return nil}))
  try FileManager.default.linkItem(at:cache,to:root.appendingPathComponent("outside-link"))
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(cache,home:home,mover:{_ in XCTFail("External hardlink must not move");return nil}))
 }
 func testDatabasePreflightRejectsLinkedDirectories() throws {
  let home=root.appendingPathComponent("home");let db=try file("home/Library/Real/db")
  try FileManager.default.createSymbolicLink(at:home.appendingPathComponent("Library/Safari"),withDestinationURL:db.deletingLastPathComponent())
  XCTAssertThrowsError(try MaintenanceBackend.databasePreflight(home:home))
 }
 func testDirectUpdateDiskImageEligibilityAndFeed() throws {
  let app=try fixtureApp(identifier:"org.fixture.App",version:"1.0")
  let xml=Data("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><enclosure url=\"https://publisher.example/App.dmg\" /></item></channel></rss>".utf8)
  let update=try AppcastMetadata.update(app:app,data:xml,feed:URL(string:"https://publisher.example/feed")!,systemVersion:"27.0")
  XCTAssertTrue(update?.usesDirectArchive ?? false);XCTAssertTrue(update?.canInstall ?? false)
  let unsupported=SoftwareUpdate(id:"fixture",name:"Fixture",installed:"1",available:"2",source:"Sparkle",information:"",applicationURL:app.url,downloadURL:URL(string:"https://publisher.example/App.pkg"))
  XCTAssertFalse(unsupported.usesDirectArchive)
 }
 func testPublicCatalogDirectDownloadsRequireChecksumAndNoScripts() throws {
  let app=try fixtureApp(identifier:"md.obsidian",version:"1.0")
  let hash=String(repeating:"a",count:64)
  func data(_ sha:String,_ extra:String="")->Data {Data("{\"token\":\"obsidian\",\"version\":\"1.1\",\"url\":\"https://publisher.example/Fixture.dmg\",\"sha256\":\"\(sha)\",\"artifacts\":[{\"app\":[\"Fixture.app\"],\"target\":\"/Applications/Fixture.app\"}\(extra)]}".utf8)}
  let valid=try PublicCaskUpdates.parse(data(hash),app:app)
  XCTAssertTrue(valid?.canInstall ?? false);XCTAssertEqual(valid?.downloadSHA256,hash)
  XCTAssertFalse(try PublicCaskUpdates.parse(data("no_check"),app:app)?.canInstall ?? true)
  XCTAssertFalse(try PublicCaskUpdates.parse(data(hash,",{\"preflight\":null}"),app:app)?.canInstall ?? true)
 }
 func testCatalogBuildOnlyReleaseMatchesExactBuild() {
  let item=SoftwareUpdate(id:"fixture",name:"Fixture",installed:"1.0",available:"1.0,21",source:"Website",information:"")
  XCTAssertTrue(DirectUpdates.releaseMatches(item:item,initialVersion:"1.0",initialBuild:"20",version:"1.0",build:"21"))
  XCTAssertFalse(DirectUpdates.releaseMatches(item:item,initialVersion:"1.0",initialBuild:"20",version:"1.0",build:"22"))
 }
 func testCatalogArchiveChecksumBeforeExtraction() throws {
  let archive=try file("update.dmg",64)
  let hash=SHA256.hash(data:try Data(contentsOf:archive)).map {String(format:"%02x",$0)}.joined()
  func update(_ checksum:String)->SoftwareUpdate {SoftwareUpdate(id:"catalog:fixture",name:"Fixture",installed:"1",available:"2",source:"Website",information:"",applicationURL:root.appendingPathComponent("Fixture.app"),downloadURL:URL(string:"https://publisher.example/App.dmg"),downloadSHA256:checksum)}
  XCTAssertNoThrow(try DirectUpdates.verifyArchive(archive,item:update(hash),publicKey:nil))
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:update(String(repeating:"0",count:64)),publicKey:nil))
 }
 func testDiskImageMatchingRejectsDuplicatesAndExternalLinks() throws {
  let folder=root.appendingPathComponent("volume");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let app=try fixtureApp(identifier:"org.fixture.App",version:"1")
  let copy=folder.appendingPathComponent("Fixture.app");try FileManager.default.copyItem(at:app.url,to:copy)
  XCTAssertEqual(physicalURL(try DiskImageUpdates.matchingApp(in:folder,bundleID:app.bundleID)).path,physicalURL(copy).path)
  try FileManager.default.copyItem(at:app.url,to:folder.appendingPathComponent("Duplicate.app"))
  XCTAssertThrowsError(try DiskImageUpdates.matchingApp(in:folder,bundleID:app.bundleID))
  try FileManager.default.removeItem(at:copy);try FileManager.default.removeItem(at:folder.appendingPathComponent("Duplicate.app"))
  try FileManager.default.createSymbolicLink(at:copy,withDestinationURL:app.url)
  XCTAssertThrowsError(try DiskImageUpdates.matchingApp(in:folder,bundleID:app.bundleID))
 }
 func testDiskImageReadOnlyExtractionRoundTrip() async throws {
  let app=try fixtureApp(identifier:"org.fixture.App",version:"1")
  let image=root.appendingPathComponent("update.dmg"),out=root.appendingPathComponent("extracted"),source=root.appendingPathComponent("image-source")
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
  try FileManager.default.copyItem(at:app.url,to:source.appendingPathComponent("Fixture.app"))
  let create=Process();create.executableURL=URL(fileURLWithPath:"/usr/bin/hdiutil");create.arguments=["create","-srcfolder",source.path,"-volname","BonsaiUpdateFixture","-format","UDZO","-o",image.path];create.standardOutput=FileHandle.nullDevice
  try create.run();create.waitUntilExit();XCTAssertEqual(create.terminationStatus,0)
  try await DiskImageUpdates.extract(image,to:out,bundleID:app.bundleID)
  XCTAssertEqual(Bundle(url:out.appendingPathComponent("Fixture.app"))?.bundleIdentifier,app.bundleID)
 }
 func testPublicCaskMetadataRequiresMatchingIdentityAndArtifact() throws {
  let app=try fixtureApp(identifier:"md.obsidian",version:"1.0")
  func data(_ token:String,_ artifact:String)->Data {Data("{\"token\":\"\(token)\",\"version\":\"1.1\",\"artifacts\":[{\"app\":[\"\(artifact)\"]}]}".utf8)}
  let update=try PublicCaskUpdates.parse(data("obsidian","Fixture.app"),app:app)
  XCTAssertEqual(update?.available,"1.1");XCTAssertFalse(update?.canInstall ?? true)
  XCTAssertThrowsError(try PublicCaskUpdates.parse(data("wrong","Fixture.app"),app:app))
  XCTAssertThrowsError(try PublicCaskUpdates.parse(data("obsidian","Wrong.app"),app:app))
 }
 func testUpdateDiscoveryIncludesAppsWithoutDeclaredFeed() async throws {
  let app=try fixtureApp(identifier:"md.obsidian",version:"1.0")
  let report=try await UpdateDiscovery.check([app],consent:true,publicCatalogConsent:true,fetch:{url in
   XCTAssertEqual(url.host,"formulae.brew.sh")
   return Data("{\"token\":\"obsidian\",\"version\":\"1.1\",\"artifacts\":[{\"app\":[\"Fixture.app\"]}]}".utf8)
  })
  XCTAssertEqual(report.updates.count,1);XCTAssertEqual(report.checked,1)
 }
 func testUpdateAllFailureContinuesAndHandoffsAreNotInstallations() async {
  let cask=SoftwareUpdate(id:"fixture",name:"Cask",installed:"1",available:"2",source:"Homebrew cask",information:"Fixture")
  let native=SoftwareUpdate(id:"native",name:"Native",installed:"1",available:"2",source:"Website",information:"Fixture")
  let result=await SoftwareUpdateBatch.run([cask,cask,native],install:{item in ItemOutcome(title:item.name,path:item.id,status:"Failed",detail:"Fixture")},handoff:{_ in true})
  XCTAssertEqual(result.count,2);XCTAssertEqual(result.map(\.status),["Failed","Opened updater"])
 }
 func testUpdateAllCancellationDoesNotOpenOrInstallNextApp() async {
  let item=SoftwareUpdate(id:"fixture",name:"Fixture",installed:"1",available:"2",source:"Appcast",information:"")
  let worker=Task {await SoftwareUpdateBatch.run([item],progress:{_,_ in withUnsafeCurrentTask {$0?.cancel()}},install:{_ in XCTFail("Installer must not run");return ItemOutcome(title:"",path:"",status:"Failed",detail:"")},handoff:{_ in XCTFail("Updater must not open");return false})}
  let result=await worker.value;XCTAssertEqual(result.first?.status,"Skipped")
 }
 func testIncompleteSizesAreClearlyLowerBounds() {
  XCTAssertEqual(Measurement.sizeLabel(0,complete:false),"Not measured")
  XCTAssertEqual(Measurement.sizeLabel(1024,complete:false),"At least "+bytes(1024))
  XCTAssertEqual(Measurement.sizeLabel(1024,complete:true),bytes(1024))
 }
}

extension CoreTests {
 func testPublicCatalogDoesNotContactSourceWithoutSeparateConsent() async throws {
  let app=try fixtureApp(identifier:"md.obsidian",version:"1.0")
  let report=try await UpdateDiscovery.check([app],consent:true,fetch:{_ in XCTFail("Public cask request requires its own consent");return Data()})
  XCTAssertEqual(report.checked,0);XCTAssertTrue(report.updates.isEmpty)
 }
}

extension CoreTests {
 func testDiskAccountingUsesBoundedManifestAndHardlinks() async throws {
  let a=try file("folder/a"),b=root.appendingPathComponent("folder/b")
  try FileManager.default.linkItem(at:a,to:b)
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("folder/link"),withDestinationURL:URL(fileURLWithPath:"/outside"))
  let measurement=try FileScanner.measure(a.deletingLastPathComponent(),diskAccounting:true)
  XCTAssertTrue(measurement.complete);XCTAssertEqual(measurement.manifest.count,1);XCTAssertEqual(measurement.scannedNodes,4)
  let scan=try await DiskExplorer().scan(a.deletingLastPathComponent())
  XCTAssertTrue(scan.complete);XCTAssertEqual(scan.entries.count,3)
  XCTAssertEqual(scan.total,try FileScanner.measure(a).allocated)
 }
 func testRepairKeepsValidRecentRunningAndGuardedFiles() throws {
  let home=root.appendingPathComponent("home"),recovery=root.appendingPathComponent("recovered")
  let pref=try file("home/Library/Preferences/org.fixture.plist")
  try PropertyListSerialization.data(fromPropertyList:["keep":true],format:.xml,options:0).write(to:pref)
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(pref,home:home,mover:{_ in XCTFail("Valid preferences must stay");return nil}))
  try Data("corrupted fixture".utf8).write(to:pref)
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(pref,home:home,runningIDs:["org.fixture"],mover:{_ in XCTFail("Running app");return nil}))
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(pref,home:home,exclusions:[pref.path],mover:{_ in XCTFail("Guarded file");return nil}))
  XCTAssertEqual(try MaintenanceCacheTrash.move(pref,home:home,mover:{u in try FileManager.default.moveItem(at:u,to:recovery);return recovery}),recovery)
  XCTAssertEqual(try String(contentsOf:recovery,encoding:.utf8),"corrupted fixture")
  let state=try file("home/Library/Saved Application State/org.fixture.savedState/data").deletingLastPathComponent()
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(state,home:home,mover:{_ in XCTFail("Recent state");return nil}))
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow: -33*86400)],ofItemAtPath:state.path)
  let stateRecovery=root.appendingPathComponent("state-recovery")
  XCTAssertEqual(try MaintenanceCacheTrash.move(state,home:home,mover:{u in try FileManager.default.moveItem(at:u,to:stateRecovery);return stateRecovery}),stateRecovery)
 }
 func testAppStoreIdentifiersAndSourceLabels() {
  let valid=SoftwareUpdate(id:"store:org.fixture.App",name:"Fixture",installed:"1",available:"2",source:"App Store",information:"")
  XCTAssertEqual(StoreUpdates.bundleID(valid),"org.fixture.App");XCTAssertTrue(valid.canInstall)
  for id in ["store:-bad","store:org.fixture;rm","store:org.fixture\n", "other:org.fixture"] {
   XCTAssertNil(StoreUpdates.bundleID(SoftwareUpdate(id:id,name:"Fixture",installed:"1",available:"2",source:"App Store",information:"")))
  }
  for (source,label) in [("Appcast","Sparkle"),("Sparkle","Sparkle"),("Homebrew cask","Homebrew"),("Homebrew tap","Homebrew"),("Electron","Electron"),("Website","Website")] {
   XCTAssertEqual(SoftwareUpdate(id:"fixture",name:"Fixture",installed:"1",available:"2",source:source,information:"").sourceLabel,label)
  }
 }
 func testUnsignedReplacementIsNeverTrusted() throws {
  let original=try fixtureApp(identifier:"org.fixture.original",version:"1")
  XCTAssertThrowsError(try DirectUpdates.verifyPublisher(installed:original.url,candidate:original.url))
 }
}

extension CoreTests {
 func testUpdateArchiveNormal() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQBH3dx5AgAAAAIAAAARAAAAQXBwL0NvbnRlbnRzL2ZpbGVva1BLAQIUAxQAAAAAAAAAIQBH3dx5AgAAAAIAAAARAAAAAAAAAAAAAACkgQAAAABBcHAvQ29udGVudHMvZmlsZVBLBQYAAAAAAQABAD8AAAAxAAAAAAA=")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertNoThrow(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
 func testUpdateArchiveTraversal() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQD7OSuCAwAAAAMAAAAKAAAALi4vb3V0c2lkZWJhZFBLAQIUAxQAAAAAAAAAIQD7OSuCAwAAAAMAAAAKAAAAAAAAAAAAAACkgQAAAAAuLi9vdXRzaWRlUEsFBgAAAAABAAEAOAAAACsAAAAAAA==")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertThrowsError(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
 func testUpdateArchiveAbsolute() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQD7OSuCAwAAAAMAAAASAAAAL3RtcC9ib25zYWktZXNjYXBlYmFkUEsBAhQDFAAAAAAAAAAhAPs5K4IDAAAAAwAAABIAAAAAAAAAAAAAAKSBAAAAAC90bXAvYm9uc2FpLWVzY2FwZVBLBQYAAAAAAQABAEAAAAAzAAAAAAA=")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertThrowsError(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
 func testUpdateArchiveLinkEscape() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQBASv+xDQAAAA0AAAAIAAAAQXBwL2xpbmsuLi8uLi9vdXRzaWRlUEsBAhQDFAAAAAAAAAAhAEBK/7ENAAAADQAAAAgAAAAAAAAAAAAAAP+hAAAAAEFwcC9saW5rUEsFBgAAAAABAAEANgAAADMAAAAAAA==")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertThrowsError(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
 func testUpdateArchiveLinkWrite() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQBC4tQOAQAAAAEAAAAIAAAAQXBwL2xpbmsuUEsDBBQAAAAAAAAAIQD7OSuCAwAAAAMAAAAQAAAAQXBwL2xpbmsvZXNjYXBlZGJhZFBLAQIUAxQAAAAAAAAAIQBC4tQOAQAAAAEAAAAIAAAAAAAAAAAAAAD/oQAAAABBcHAvbGlua1BLAQIUAxQAAAAAAAAAIQD7OSuCAwAAAAMAAAAQAAAAAAAAAAAAAACkgScAAABBcHAvbGluay9lc2NhcGVkUEsFBgAAAAACAAIAdAAAAFgAAAAAAA==")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertThrowsError(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
 func testUpdateArchiveInternalLink() throws {
  let archive=root.appendingPathComponent("update.zip"),destination=root.appendingPathComponent("out")
  try Data(base64Encoded:"UEsDBBQAAAAAAAAAIQBH3dx5AgAAAAIAAAATAAAAQXBwL1ZlcnNpb25zL0EvZmlsZW9rUEsDBBQAAAAAAAAAIQCLntnTAQAAAAEAAAAUAAAAQXBwL1ZlcnNpb25zL0N1cnJlbnRBUEsBAhQDFAAAAAAAAAAhAEfd3HkCAAAAAgAAABMAAAAAAAAAAAAAAKSBAAAAAEFwcC9WZXJzaW9ucy9BL2ZpbGVQSwECFAMUAAAAAAAAACEAi57Z0wEAAAABAAAAFAAAAAAAAAAAAAAA/6EzAAAAQXBwL1ZlcnNpb25zL0N1cnJlbnRQSwUGAAAAAAIAAgCDAAAAZgAAAAAA")!.write(to:archive)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  XCTAssertNoThrow(try DirectUpdates.extract(archive,to:destination))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("outside").path))
 }
}

extension CoreTests {
 func testFinderRepairProtectsRecentDocumentsAndHealthyLists() throws {
  let home=root.appendingPathComponent("home")
  let recent=try file("home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/fixture.sfl3")
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(recent,home:home,mover:{_ in XCTFail("Recent documents must remain");return nil}))
  let list=try file("home/Library/Application Support/com.apple.sharedfilelist/fixture.sfl3")
  try PropertyListSerialization.data(fromPropertyList:["keep":true],format:.binary,options:0).write(to:list)
  XCTAssertThrowsError(try MaintenanceCacheTrash.move(list,home:home,mover:{_ in XCTFail("Valid list must remain");return nil}))
  try Data("<plist><broken".utf8).write(to:list)
  let recovery=root.appendingPathComponent("list-recovery")
  XCTAssertEqual(try MaintenanceCacheTrash.move(list,home:home,mover:{u in try FileManager.default.moveItem(at:u,to:recovery);return recovery}),recovery)
 }
 func testElectronArchiveRequiresCompatibleArchiveAndDigest() {
  let hash=Data(repeating:1,count:64).base64EncodedString(),source=URL(string:"https://example.com/releases/latest-mac.yml")!
  let manifest=Data(("version: 2.0\nfiles:\n  - url: Fixture-x64.zip\n    sha512: "+hash+"\n  - url: Fixture-arm64.zip\n    sha512: "+hash+"\n").utf8)
  XCTAssertEqual(ElectronMetadata.archive(manifest,source:source)?.0.absoluteString,"https://example.com/releases/Fixture-arm64.zip")
  for path in ["Fixture-x64.zip","Fixture.pkg","http://example.com/file.zip","https://localhost/file.zip"] {
   XCTAssertNil(ElectronMetadata.archive(Data(("path: "+path+"\nsha512: "+hash).utf8),source:source))
  }
  XCTAssertEqual(ElectronMetadata.archive(Data(("path: Fixture.dmg\nsha512: "+hash).utf8),source:source)?.0.pathExtension,"dmg")
  XCTAssertNil(ElectronMetadata.archive(Data("path: Fixture.zip\nsha512: invalid".utf8),source:source))
 }
}

extension CoreTests {
 func testDiskTrashDoesNotReportNoOpAsSuccess() throws {
  let url=try file("still-here")
  let entry=DiskEntry(url:url,directory:false,measurement:try FileScanner.measure(url))
  let result=DiskTrash.perform(try DiskTrashRequest(entry),policy:PathPolicy(roots:[root]),mover:{_ in nil})
  XCTAssertEqual(result.status,"Skipped");XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
 }
}

extension CoreTests {
 func testContainerDiscoverySkipsHiddenAndNonDirectories() throws {
  _=try file("Library/Containers/.DS_Store")
  _=try file("Library/Containers/org.fixture.not-a-folder")
  let report=try CleanCatalog.scan(home:root,temporaryRoot:root.appendingPathComponent("temporary"))
  XCTAssertFalse(report.issues.contains {$0.contains(".DS_Store") || $0.contains("not-a-folder")})
 }
 func testAccessRoutingPrefersPrivacyOverKnownLockedFolder() throws {
  let locked=try file("locked");try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:locked.path)
  defer {try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:locked.path)}
  let readable=try file("protected-cache")
  XCTAssertEqual(FileAccess.preferredDeniedURL([locked.path,readable.path]),readable)
 }
 func testDiskInventoryRetainsHiddenEmptyAndGroupedEntries() async throws {
  _=try file(".hidden-cache",8192);_=try file("empty-file",0)
  try FileManager.default.createDirectory(at:root.appendingPathComponent(".hidden-folder"),withIntermediateDirectories:true)
  for index in 0..<28 {_=try file("item-\(index)",4096)}
  let scan=try await DiskExplorer().scan(root)
  XCTAssertEqual(scan.entries.count,31)
  XCTAssertTrue(scan.entries.contains {$0.url.lastPathComponent==".hidden-cache"})
  XCTAssertTrue(scan.entries.contains {$0.url.lastPathComponent==".hidden-folder"})
  XCTAssertTrue(scan.entries.contains {$0.url.lastPathComponent=="empty-file" && $0.measurement.allocated==0})
  let grouped=DiskMapGroup.make(scan.entries)
  XCTAssertEqual(grouped.count,9)
  XCTAssertEqual(grouped.flatMap(\.entries).count,29)
  XCTAssertEqual(grouped.reduce(0) {$0+$1.weight},scan.total)
 }
 func testDiskMapKeepsLargestEightAndGroupsRemainder() {
  let entries=(0..<20).map {i -> DiskEntry in var size=Measurement();size.allocated=1_000_000;return DiskEntry(url:root.appendingPathComponent("Folder \(i)"),directory:true,measurement:size)}
  let groups=DiskMapGroup.make(entries)
  XCTAssertEqual(groups.count,9)
  XCTAssertTrue(groups.prefix(8).allSatisfy {!$0.isRemainder && $0.entries.count==1})
  XCTAssertTrue(groups.last!.isRemainder);XCTAssertEqual(groups.last!.title,"12 items")
  XCTAssertEqual(groups.flatMap(\.entries).count,20)
  XCTAssertEqual(groups.reduce(0) {$0+$1.weight},20_000_000)
  XCTAssertEqual(groups.last!.label,bytes(12_000_000))
  XCTAssertEqual(Set(groups.flatMap(\.entries).map(\.id)).count,20)
 }

 func testDiskMapLabelsUseMeasuredWeightsAndKeepCompleteness() {
  var size=Measurement();size.allocated=1_048_576;size.complete=false
  let partial=DiskEntry(url:root.appendingPathComponent("Protected"),directory:true,measurement:size)
  let groups=DiskMapGroup.make([partial])
  XCTAssertEqual(groups.count,1)
  XCTAssertEqual(groups[0].label,bytes(size.allocated))
  XCTAssertEqual(groups[0].weight,size.allocated)
  XCTAssertFalse(groups[0].entries[0].measurement.complete)
  var unknown=Measurement();unknown.complete=false
  let unmeasured=DiskEntry(url:root.appendingPathComponent("Unreadable"),directory:true,measurement:unknown)
  XCTAssertEqual(unmeasured.label,"Unknown size")
  XCTAssertTrue(DiskMapGroup.make([unmeasured]).isEmpty)
 }

 func testPrivacyGrantDoesNotMasqueradeAsAccessToEveryFolder() throws {
  let location=root.appendingPathComponent("restricted-group")
  try FileManager.default.createDirectory(at:location,withIntermediateDirectories:true)
  try FileManager.default.setAttributes([.posixPermissions:0o750],ofItemAtPath:location.path)
  let identity=try Identity.read(location)
  XCTAssertEqual(FileAccessNeed(url:location,operation:"Analyze",uid:getuid() &+ 1,identity:identity,groups:[]).route,.filePermissions)
  XCTAssertEqual(FileAccessNeed(url:location,operation:"Analyze",uid:getuid() &+ 1,identity:identity,groups:FileAccess.currentGroups()).route,.fullDiskAccess)
  XCTAssertEqual(FileAccessNeed(url:location,operation:"Analyze",uid:getuid() &+ 1,identity:identity,groups:FileAccess.currentGroups(),privacyReadable:true).route,.systemProtection)
  XCTAssertEqual(FileAccessNeed(url:root.appendingPathComponent("Library/Apple-protected"),operation:"Analyze",privacyReadable:true).route,.systemProtection)
  XCTAssertEqual(FileAccessNeed(url:root.appendingPathComponent("Documents/data"),operation:"Clean",home:root,privacyReadable:true).route,.filesAndFolders)
 }

 func testUpdatedAppMetadataIsReadFresh() throws {
  let app=try fixtureApp(),file=app.url.appendingPathComponent("Contents/Info.plist")
  var info=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),format:nil) as! [String:Any]
  info["CFBundleShortVersionString"]="9.8.7"
  try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:file)
  let refreshed=try AppInventory.refreshed(app)
  XCTAssertEqual(refreshed.version,"9.8.7");XCTAssertEqual(refreshed.bundleID,app.bundleID)
  info["CFBundleIdentifier"]="different.publisher"
  try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:file)
  XCTAssertThrowsError(try AppInventory.refreshed(app))
 }

 func testSparkleFullArchiveMetadataAndDeltaIsolation() throws {
  let app=try fixtureApp()
  let xml=Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://updates.example.com/App.zip" length="123" sparkle:version="21" sparkle:shortVersionString="1.1" sparkle:edSignature="fixture"/><sparkle:deltas><enclosure url="https://updates.example.com/App.delta" sparkle:deltaFrom="20" sparkle:version="21"/></sparkle:deltas></item></channel></rss>"#.utf8)
  let update=try AppcastMetadata.update(app:app,data:xml,feed:URL(string:"https://updates.example.com/feed.xml")!,systemVersion:"14.0")
  XCTAssertEqual(update?.downloadURL?.lastPathComponent,"App.zip")
  XCTAssertEqual(update?.downloadBytes,123);XCTAssertEqual(update?.downloadSignature,"fixture");XCTAssertEqual(update?.availableBuild,"21")
  XCTAssertTrue(update?.usesDirectArchive ?? false);XCTAssertTrue(update?.canInstall ?? false)
  let package=Data(String(decoding:xml,as:UTF8.self).replacingOccurrences(of:"length=\"123\"",with:"sparkle:installationType=\"package\"").utf8)
  XCTAssertNil(try AppcastMetadata.update(app:app,data:package,feed:URL(string:"https://updates.example.com/feed.xml")!,systemVersion:"14.0")?.downloadURL)
 }
 func testSparkleArchiveRequiresDeclaredKeySignatureAndLength() throws {
  let archive=try file("publisher.zip",512),data=try Data(contentsOf:archive)
  let key=Curve25519.Signing.PrivateKey();let signature=try key.signature(for:data).base64EncodedString()
  func item(_ signature:String?,_ count:UInt64=512)->SoftwareUpdate {SoftwareUpdate(id:"signed",name:"Fixture",installed:"1.0",available:"1.1",source:"Sparkle",information:"",downloadSignature:signature,downloadBytes:count)}
  let publicKey=key.publicKey.rawRepresentation.base64EncodedString()
  XCTAssertNoThrow(try DirectUpdates.verifyArchive(archive,item:item(signature),publicKey:publicKey))
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:item(nil),publicKey:publicKey))
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:item(signature),publicKey:Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:item(signature,511),publicKey:publicKey))
  try Data(repeating:43,count:512).write(to:archive)
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:item(signature),publicKey:publicKey))
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:item(signature),publicKey:"invalid"))
  // Legacy ZIP authenticity is decided by mandatory publisher code validation.
  XCTAssertNoThrow(try DirectUpdates.verifyArchive(archive,item:item(nil),publicKey:nil))
  let link=root.appendingPathComponent("linked.zip");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:archive)
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(link,item:item(nil),publicKey:nil))
 }
 func testDirectUpdateVersionBuildAndSourceRules() {
  let app=root.appendingPathComponent("Fixture.app"),url=URL(string:"https://updates.example.com/App.zip")!
  let item=SoftwareUpdate(id:"same-version",name:"Fixture",installed:"1.0",available:"1.0",source:"Sparkle",information:"",applicationURL:app,downloadURL:url,availableBuild:"21")
  XCTAssertTrue(item.canInstall)
  XCTAssertTrue(DirectUpdates.releaseMatches(item:item,initialVersion:"1.0",initialBuild:"20",version:"1.0",build:"21"))
  XCTAssertFalse(DirectUpdates.releaseMatches(item:item,initialVersion:"1.0",initialBuild:"21",version:"1.0",build:"21"))
  XCTAssertFalse(DirectUpdates.releaseMatches(item:item,initialVersion:"1.0",initialBuild:"20",version:"1.0",build:"22"))
  XCTAssertFalse(DirectUpdates.releaseMatches(item:item,initialVersion:"1.1",initialBuild:"20",version:"1.0",build:"21"))
  XCTAssertFalse(SoftwareUpdate(id:"web",name:"Fixture",installed:"1.0",available:"2.0",source:"Website",information:"",applicationURL:app,downloadURL:url).usesDirectArchive)
  XCTAssertFalse(SoftwareUpdate(id:"http",name:"Fixture",installed:"1.0",available:"2.0",source:"Sparkle",information:"",applicationURL:app,downloadURL:URL(string:"http://updates.example.com/App.zip")).usesDirectArchive)
  let stored=try? JSONEncoder().encode(item);let decoded=stored.flatMap {try? JSONDecoder().decode(SoftwareUpdate.self,from:$0)}
  XCTAssertEqual(decoded?.availableBuild,"21");XCTAssertTrue(decoded?.usesDirectArchive ?? false)
 }
 func testElectronDirectArchiveKeepsChecksumRequirement() throws {
  let archive=try file("electron.zip",128);let data=try Data(contentsOf:archive)
  let good=SoftwareUpdate(id:"electron",name:"Fixture",installed:"1.0",available:"2.0",source:"Electron",information:"",downloadSHA512:Data(SHA512.hash(data:data)).base64EncodedString())
  XCTAssertNoThrow(try DirectUpdates.verifyArchive(archive,item:good,publicKey:nil))
  let bad=SoftwareUpdate(id:"electron",name:"Fixture",installed:"1.0",available:"2.0",source:"Electron",information:"")
  XCTAssertThrowsError(try DirectUpdates.verifyArchive(archive,item:bad,publicKey:nil))
 }

}
