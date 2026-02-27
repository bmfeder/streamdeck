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
        .library(name: "Database", targets: ["Database"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "Repositories", targets: ["Repositories"]),
        .library(name: "EmbyClient", targets: ["EmbyClient"]),
        .library(name: "SyncDatabase", targets: ["SyncDatabase"]),
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
        .package(
            url: "https://github.com/powersync-ja/powersync-swift",
            from: "1.11.0"
        ),
        .package(
            url: "https://github.com/supabase/supabase-swift",
            from: "2.41.0"
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
        .target(
            name: "Database",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Database"
        ),
        .target(
            name: "SyncDatabase",
            dependencies: [
                .product(name: "PowerSync", package: "powersync-swift"),
                .product(name: "Supabase", package: "supabase-swift"),
                "Database",
            ],
            path: "Sources/SyncDatabase"
        ),
        .target(
            name: "AppFeature",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "VLCKitSPM", package: "vlckit-spm", condition: .when(platforms: [.tvOS, .iOS])),
                "Repositories",
                "SyncDatabase",
            ],
            path: "Sources/AppFeature"
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
        .testTarget(
            name: "DatabaseTests",
            dependencies: ["Database"],
            path: "Tests/DatabaseTests"
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"],
            path: "Tests/AppFeatureTests"
        ),
        .target(
            name: "EmbyClient",
            dependencies: ["XtreamClient"],
            path: "Sources/EmbyClient"
        ),
        .target(
            name: "Repositories",
            dependencies: ["Database", "M3UParser", "XtreamClient", "XMLTVParser", "EmbyClient"],
            path: "Sources/Repositories"
        ),
        .testTarget(
            name: "EmbyClientTests",
            dependencies: ["EmbyClient"],
            path: "Tests/EmbyClientTests"
        ),
        .testTarget(
            name: "RepositoryTests",
            dependencies: ["Repositories"],
            path: "Tests/RepositoryTests"
        ),
        .testTarget(
            name: "SyncDatabaseTests",
            dependencies: ["SyncDatabase"],
            path: "Tests/SyncDatabaseTests"
        ),
    ]
)
