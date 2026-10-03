// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Y-Downloader",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/AdguardTeam/SafariConverterLib.git", from: "4.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Y-Downloader",
            dependencies: [
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib")
            ],
            path: "Y-Downloader",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "Y-DownloaderTests",
            dependencies: ["Y-Downloader"],
            path: "Tests"
        )
    ]
)
