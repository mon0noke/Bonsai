import Foundation
import BonsaiCore
@main struct CompareSize {
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("Bonsai-sizing-"+UUID().uuidString).resolvingSymlinksInPath()
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
  defer {try? FileManager.default.removeItem(at:root)}
  for index in 0..<4000 {
   let folder=root.appendingPathComponent("group-\(index%20)");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   try Data(repeating:UInt8(index%255),count:4096+index%8192).write(to:folder.appendingPathComponent("file-\(index)"))
  }
  try FileManager.default.linkItem(at:root.appendingPathComponent("group-0/file-0"),to:root.appendingPathComponent("hardlink"))
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("outside-link"),withDestinationURL:URL(fileURLWithPath:"/Applications"))
  let started=ProcessInfo.processInfo.systemUptime
  let result=try await DiskExplorer().scan(root,refresh:true)
  let elapsed=ProcessInfo.processInfo.systemUptime-started
  let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/du");process.arguments=["-skP",root.path];process.standardOutput=pipe;try process.run();let output=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);process.waitUntilExit();precondition(process.terminationStatus==0)
  let expected=UInt64(output.split(whereSeparator:{$0.isWhitespace}).first ?? "")! * 1024
  precondition(result.complete && result.total==expected,"Measured allocation must equal system du for isolated fixture")
  print("PASS: 4,000 files / 20 folders, hardlink and external symlink, complete scan; \(result.total) allocated bytes equals du; \(elapsed) seconds")
 }
}
