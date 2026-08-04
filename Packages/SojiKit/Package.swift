// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SojiKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SojiKit", targets: ["SojiKit"]),
        // GUI と同じロジックの上に立つ CLI。GUI でできることは CLI でもできる。
        .executable(name: "soji", targets: ["soji"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "SojiKit",
            swiftSettings: [
                // Why not MainActor: Xcode 26 の新規プロジェクト既定は
                // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor。それだとスキャナが
                // 丸ごと MainActor に載って UI を止める。SojiKit は UI を持たない
                // ので nonisolated を既定にする。個々の関数に @concurrent を貼って
                // 回るより漏れがない (app ターゲット側は逆に MainActor 既定)。
                .defaultIsolation(nil),
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "soji",
            dependencies: [
                "SojiKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .defaultIsolation(nil),
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SojiKitTests",
            dependencies: ["SojiKit"],
            swiftSettings: [
                .defaultIsolation(nil),
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
