// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageMenubar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AIUsageMenubar", targets: ["AIUsageMenubar"]),
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "AIUsageMenubar", dependencies: ["UsageCore"], resources: [.process("Resources")]),
        .executableTarget(name: "UsageCoreChecks", dependencies: ["UsageCore"], path: "Tests/UsageCoreChecks")
    ]
)
