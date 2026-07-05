// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "墨读",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "墨读",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            resources: [
                .copy("MarkdownReader/Resources/vditor"),
                .copy("MarkdownReader/Resources/vditor-editor"),
            ]
        ),
    ]
)
