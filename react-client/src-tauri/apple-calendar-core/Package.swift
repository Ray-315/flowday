// swift-tools-version:5.7
import PackageDescription
let package = Package(name: "FlowCalendarCore", platforms: [.macOS(.v11), .iOS(.v15)],
  products: [.library(name: "FlowCalendarCore", type: .static, targets: ["FlowCalendarCore"])],
  targets: [.target(name: "FlowCalendarCore")])
