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
