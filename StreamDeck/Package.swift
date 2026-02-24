// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "M3UParser", targets: ["M3UParser"]),
        .library(name: "XtreamClient", targets: ["XtreamClient"]),
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
    ]
)
