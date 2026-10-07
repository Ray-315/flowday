// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "tauri-plugin-live-activity",
    platforms: [.iOS(.v15)],
    products: [.library(name: "tauri-plugin-live-activity", type: .static, targets: ["LiveActivityPlugin"])],
    dependencies: [.package(name: "Tauri", path: "../.tauri/tauri-api")],
    targets: [.target(name: "LiveActivityPlugin", dependencies: [.byName(name: "Tauri")], path: "Sources")]
)
