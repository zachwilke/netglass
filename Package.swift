// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetglassCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NetglassCore", targets: ["NetglassCore"])
    ],
    targets: [
        .target(
            name: "NetglassCore",
            path: "Netglass",
            sources: [
                "Models/CommandSpec.swift",
                "Models/ToolKind.swift",
                "Services/ArgumentPolicy.swift",
                "Services/BinaryLocator.swift",
                "Services/ConsoleText.swift",
                "Services/InputValidator.swift",
                "Services/ReportExport.swift"
            ]
        ),
        .testTarget(
            name: "NetglassCoreTests",
            dependencies: ["NetglassCore"],
            path: "Tests/NetglassCoreTests"
        )
    ]
)
