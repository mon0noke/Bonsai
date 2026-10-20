import Foundation
import BonsaiCore
@main struct Verify {
 static func main() throws {
  let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:home) }
  let suite="bonsai.migration.fixture."+UUID().uuidString
  let previous=suite+".previous"
  let defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite); defaults.removePersistentDomain(forName:previous) }
  defaults.setPersistentDomain(["existing":"keep"],forName:suite)
  defaults.setPersistentDomain(["existing":"old","theme":"sakura"],forName:previous)
  BrandingMigration.run(defaults:defaults,home:home,domain:suite,previousDomain:previous)
  var saved=defaults.persistentDomain(forName:suite)!
  precondition(saved["existing"] as? String == "keep")
  precondition(saved["theme"] as? String == "sakura")
  let source=home.appendingPathComponent("Library/Application Support/"+AppIdentity.protectedFolderNames[1]+"/history.json")
  try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data("[]".utf8).write(to:source)
  BrandingMigration.run(defaults:defaults,home:home,domain:suite,previousDomain:previous)
  let target=home.appendingPathComponent(AppIdentity.historyPath)
  let initial = try Data(contentsOf:target); precondition(initial == Data("[]".utf8))
  precondition(FileManager.default.fileExists(atPath:source.path))
  try Data("[ ]".utf8).write(to:target)
  defaults.setPersistentDomain(["theme":"changed"],forName:previous)
  BrandingMigration.run(defaults:defaults,home:home,domain:suite,previousDomain:previous)
  saved=defaults.persistentDomain(forName:suite)!
  precondition(saved["theme"] as? String == "sakura")
  let final = try Data(contentsOf:target); precondition(final == Data("[ ]".utf8))
  precondition(defaults.persistentDomain(forName:previous)?["theme"] as? String == "changed")
  print("PASS: migration preserves current preferences, copies history on retry, retains originals, and does not overwrite migrated data.")
 }
}
