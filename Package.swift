// swift-tools-version: 5.9
import PackageDescription
import Foundation
let directSparkle = !(ProcessInfo.processInfo.environment["BONSAI_SIGN_IDENTITY"] ?? "-").elementsEqual("-")
let updateFlags:[SwiftSetting] = directSparkle ? [.define("BONSAI_DIRECT_SPARKLE")] : []
let package = Package(name: "Bonsai", platforms: [.macOS(.v14)], products: [
 .executable(name: "Bonsai", targets: ["Bonsai"]), .executable(name: "BonsaiVerify", targets: ["BonsaiVerify"])
], targets: [
 .target(name: "CBonsai", linkerSettings: [.linkedLibrary("archive"), .linkedFramework("IOKit"), .linkedFramework("Security")]),
 .target(name: "BonsaiCore", dependencies: ["CBonsai"],swiftSettings:updateFlags),
 .executableTarget(name: "Bonsai", dependencies: [.target(name:"BonsaiCore")]+(directSparkle ? [.target(name:"Sparkle")] : []),swiftSettings:updateFlags),
 .binaryTarget(name:"Sparkle",path:"Vendor/Sparkle.xcframework"),
 .executableTarget(name: "BonsaiVerify", dependencies: ["BonsaiCore"]),
 .executableTarget(name: "BonsaiMaintenanceTrash", dependencies: ["BonsaiCore"]),
 .executableTarget(name: "BonsaiStoreUpdate", linkerSettings: [.linkedFramework("Security"),.linkedFramework("CoreFoundation")]),
 .testTarget(name: "BonsaiCoreTests", dependencies: ["BonsaiCore"])
])
