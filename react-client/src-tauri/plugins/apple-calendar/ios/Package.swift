// swift-tools-version:5.7
import PackageDescription
let package = Package(name: "tauri-plugin-apple-calendar", platforms: [.iOS(.v15), .macOS(.v11)],
 products: [.library(name: "tauri-plugin-apple-calendar", type: .static, targets: ["AppleCalendarPlugin"])],
 dependencies: [.package(name: "Tauri", path: "../.tauri/tauri-api"), .package(name: "FlowCalendarCore", path: "../../../apple-calendar-core")],
 targets: [.target(name: "AppleCalendarPlugin", dependencies: [.byName(name: "Tauri"), .byName(name: "FlowCalendarCore")], path: "Sources")])
