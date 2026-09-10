// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteboardMemory",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PasteboardMemory", targets: ["PasteboardMemory"])
    ],
    targets: [
        .executableTarget(
            name: "PasteboardMemory",
            path: "Sources/PasteboardMemory"
        )
    ],
    swiftLanguageModes: [.v5]
)
