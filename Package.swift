// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UmamiBar", platforms: [.macOS(.v10_15)], products: [.executable(name: "UmamiBar", targets: ["UmamiBar"])], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")], targets: [.executableTarget(name: "UmamiBar", dependencies: [.product(name: "Sparkle", package: "Sparkle")]), .testTarget(name: "UmamiBarTests", dependencies: ["UmamiBar"])])
