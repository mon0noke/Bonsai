import Foundation
import AppKit
import BonsaiCore
import Darwin
// Narrow maintenance allowlist; ownership, identity, exclusions and running apps are rechecked.
do {
    guard CommandLine.arguments.count==2 else {throw BonsaiError.refused("Expected one maintenance path.")}
    let target=URL(fileURLWithPath:CommandLine.arguments[1])
    let destination=try MaintenanceCacheTrash.move(target,runningIDs:Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),exclusions:UserDefaults(suiteName:AppIdentity.bundleIdentifier)?.stringArray(forKey:"exclusions") ?? [])
    print("Moved to Trash: \(target.path)\nRestore from: \(destination?.path ?? "your Trash")")
} catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
