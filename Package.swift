// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SSHConfigEditor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SSHConfigEditor", targets: ["SSHConfigEditor"])],
    targets: [
        .target(name: "SSHConfigCore"),
        .executableTarget(name: "SSHConfigEditor", dependencies: ["SSHConfigCore"]),
        .testTarget(name: "SSHConfigCoreTests", dependencies: ["SSHConfigCore"]),
        .testTarget(name: "SSHConfigEditorTests", dependencies: ["SSHConfigEditor"])
    ]
)
