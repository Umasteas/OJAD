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
        // Apple platforms ship SQLite as the `SQLite3` module; Linux needs libsqlite3-dev.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(
            name: "OJADKit",
            dependencies: [
                "SwiftSoup",
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "OJADKitTests",
            dependencies: ["OJADKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
