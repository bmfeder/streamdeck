// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "M3UParser", targets: ["M3UParser"]),
        .library(name: "XtreamClient", targets: ["XtreamClient"]),
        .library(name: "XMLTVParser", targets: ["XMLTVParser"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.23.1"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.10.0"
        ),
        .package(
            url: "https://github.com/tylerjonesio/vlckit-spm",
            from: "3.6.0"
        ),
    ],
    targets: [
        .target(
            name: "M3UParser",
            path: "Sources/M3UParser"
        ),
        .target(
            name: "XtreamClient",
            path: "Sources/XtreamClient"
        ),
        .target(
            name: "XMLTVParser",
            path: "Sources/XMLTVParser"
        ),
        .testTarget(
            name: "M3UParserTests",
            dependencies: ["M3UParser"],
            path: "Tests/M3UParserTests"
        ),
        .testTarget(
            name: "XtreamClientTests",
            dependencies: ["XtreamClient"],
            path: "Tests/XtreamClientTests"
        ),
        .testTarget(
            name: "XMLTVParserTests",
            dependencies: ["XMLTVParser"],
            path: "Tests/XMLTVParserTests"
        ),
    ]
)
