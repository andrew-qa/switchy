// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchy",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic + thin system wrappers (TIS, CGEventTap). Everything testable lives here.
        .target(name: "SwitchyCore"),
        // Menu bar app: AppKit status item + SwiftUI settings window.
        .executableTarget(name: "Switchy", dependencies: ["SwitchyCore"]),
        .testTarget(name: "SwitchyCoreTests", dependencies: ["SwitchyCore"]),
    ]
)
