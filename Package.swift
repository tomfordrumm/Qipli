// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Qipli",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Qipli", targets: ["Qipli"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        )
    ],
    targets: [
        .executableTarget(
            name: "Qipli",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
