// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Aero",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Aero",
            path: "Sources/Aero",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
