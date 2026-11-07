// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "baterai-safer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]),
        .executableTarget(
            name: "baterai-safer",
            dependencies: ["CSMC"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
