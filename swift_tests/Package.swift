// swift-tools-version:5.9
// Test harness for the app's pure game-logic layer.
//
// JutsuManager and AppModels have no UIKit/SwiftUI/camera dependencies, so
// they compile as a plain SwiftPM target on macOS. The source files are
// symlinked from naruto_app/ — there is exactly one copy of the logic.
//
// Run:  cd swift_tests && swift test
import PackageDescription

let package = Package(
    name: "JutsuCore",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "JutsuCore", path: "Sources/JutsuCore"),
        .testTarget(
            name: "JutsuCoreTests",
            dependencies: ["JutsuCore"],
            path: "Tests/JutsuCoreTests"
        ),
    ]
)
