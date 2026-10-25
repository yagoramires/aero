// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do checkout do neyhub ao lado (ou NEYHUB_PATH). A identidade de `.package(path:)` é o nome
// da pasta em minúsculas, então derivamos dela: funciona com worktrees.
let neyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub"
let hub = URL(fileURLWithPath: neyhub).lastPathComponent.lowercased()
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Aero",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aero", targets: ["Aero"]),
        .library(name: "AeroPlugin", type: .dynamic, targets: ["AeroPlugin"]),
    ],
    dependencies: [.package(path: neyhub)],
    targets: [
        .target(
            name: "AeroCore",
            dependencies: [.product(name: "NeyKit", package: hub)],
            path: "Sources/AeroCore",
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .executableTarget(
            name: "Aero",
            dependencies: ["AeroCore", .product(name: "NeyKitApp", package: hub)],
            path: "Sources/Aero",
            swiftSettings: swift5
        ),
        // Plugin do NeyHub: nunca linka NeyKitApp (classes duplicadas no processo do NeyHub).
        .target(name: "AeroPlugin", dependencies: ["AeroCore"], path: "Sources/AeroPlugin", swiftSettings: swift5),
    ]
)
