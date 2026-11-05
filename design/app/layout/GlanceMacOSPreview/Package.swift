// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlanceMacOSPreview",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "GlanceMacOSPreview", targets: ["GlanceMacOSPreview"])],
    targets: [.executableTarget(name: "GlanceMacOSPreview")]
)
