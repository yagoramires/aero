// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do neyhub publicado no GitHub. Para desenvolver junto com um checkout local: NEYHUB_PATH=../neyhub
// (a identidade de `.package(path:)` é o nome da pasta em minúsculas, então derivamos dela: funciona com worktrees).
let localNeyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"]
let hub = localNeyhub.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? "neyhub"
let neyhubPackage: Package.Dependency = localNeyhub.map { .package(path: $0) }
    ?? .package(url: "https://github.com/yagoramires/neyhub.git", from: "0.1.0")
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Aero",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aero", targets: ["Aero"]),
        .library(name: "AeroPlugin", type: .dynamic, targets: ["AeroPlugin"]),
    ],
    dependencies: [neyhubPackage],
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
        .target(name: "AeroPlugin", dependencies: ["AeroCore", .product(name: "NeyKit", package: hub)], path: "Sources/AeroPlugin", swiftSettings: swift5),
    ]
)
