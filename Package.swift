// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Jot", platforms: [.macOS(.v26)], products: [.executable(name: "Jot", targets: ["Jot"])], dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "04e363c29d9a754022d602d6fe1468ab80a0f705", traits: [])
], targets: [
    .target(name: "JotCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
    .executableTarget(name: "Jot", dependencies: ["JotCore"]),
    .testTarget(name: "JotTests", dependencies: ["JotCore"])
], swiftLanguageModes: [.v5])
