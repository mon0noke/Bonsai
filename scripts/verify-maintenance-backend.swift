import Foundation
import BonsaiCore
@main struct VerifyMaintenanceResource {
 static func main() async throws {
  let source=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/MaintenanceBackend")
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-backend-fixture-"+UUID().uuidString)
  try FileManager.default.copyItem(at:source,to:root);defer {try? FileManager.default.removeItem(at:root)}
  _=try MaintenanceBackend.validatedScript(directory:root)
  print("PASS pinned backend and every bundled hash validate")
  let script=root.appendingPathComponent("run.sh");let bytes=try Data(contentsOf:script)
  try Data("changed".utf8).write(to:script)
  do {_=try MaintenanceBackend.validatedScript(directory:root);fatalError("Tampered backend accepted")} catch {print("PASS modified task adapter is refused")}
  try bytes.write(to:script)
  let target=root.appendingPathComponent("lib/optimize/tasks.sh");let original=try Data(contentsOf:target)
  try FileManager.default.removeItem(at:target);try FileManager.default.createSymbolicLink(at:target,withDestinationURL:source.appendingPathComponent("lib/optimize/tasks.sh"))
  do {_=try MaintenanceBackend.validatedScript(directory:root);fatalError("Linked backend accepted")} catch {print("PASS symlinked executable resource is refused")}
  try FileManager.default.removeItem(at:target);try original.write(to:target)
  _=try MaintenanceBackend.validatedScript(directory:root)
  print("PASS restored fixture validates; production source untouched")
 }
}
