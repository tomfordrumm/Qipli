// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Qipli",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Qipli", targets: ["Qipli"])
    ],
    targets: [
        .executableTarget(
            name: "Qipli",
            path: "Sources/Qipli",
            exclude: ["Resources/Info.plist", "Resources/Qipli.entitlements"]
        ),
        .testTarget(
            name: "QipliTests",
            dependencies: ["Qipli"],
            path: "Tests/QipliTests"
        )
    ]
)
