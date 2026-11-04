// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OJADKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OJADKit", targets: ["OJADKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "OJADKit", dependencies: ["SwiftSoup"]),
        .testTarget(
            name: "OJADKitTests",
            dependencies: ["OJADKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
