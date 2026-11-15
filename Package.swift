// swift-tools-version: 6.2
import PackageDescription
import Foundation

// A Kit checkout next to this folder wins (for working on both); otherwise the published Kit.
let localKit = Context.packageDirectory + "/../Kit"
let useLocal = FileManager.default.fileExists(atPath: localKit + "/Package.swift")
let kit: Package.Dependency = useLocal
    ? .package(path: "../Kit")
    : .package(url: "https://github.com/andrewneuwirth/mac-tools-kit.git", branch: "main")
let kitPackage = useLocal ? "Kit" : "mac-tools-kit"   // SwiftPM names it after the folder or the URL

let package = Package(name: "Jot", platforms: [.macOS(.v26)], products: [.executable(name: "Jot", targets: ["Jot"])], dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "04e363c29d9a754022d602d6fe1468ab80a0f705", traits: []),
    kit
], targets: [
    .target(name: "JotCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), .product(name: "MacToolsKit", package: kitPackage)]),
    .executableTarget(name: "Jot", dependencies: ["JotCore"]),
    .testTarget(name: "JotTests", dependencies: ["JotCore"])
], swiftLanguageModes: [.v5])
