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
    // llama.cpp's prebuilt Apple framework (Metal built in) runs the dictation cleanup model; release b11998.
    .binaryTarget(name: "llama", url: "https://github.com/ggml-org/llama.cpp/releases/download/b11998/llama-b11998-xcframework.zip",
                  checksum: "48ae11bfd9681126e993ee6b69af57ca8986e4341071d266fe8a09d16da472b8"),
    .target(name: "JotCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), .product(name: "MacToolsKit", package: kitPackage), .product(name: "MacToolsUpdates", package: kitPackage), "llama"]),
    .executableTarget(name: "Jot", dependencies: ["JotCore"]),
    .testTarget(name: "JotTests", dependencies: ["JotCore"])
], swiftLanguageModes: [.v5])
