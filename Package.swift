// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UmamiBar", platforms: [.macOS(.v10_15)], products: [.executable(name: "UmamiBar", targets: ["UmamiBar"])], targets: [.executableTarget(name: "UmamiBar"), .testTarget(name: "UmamiBarTests", dependencies: ["UmamiBar"])])
