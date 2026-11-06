// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KodmozScreen",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KodmozScreen", targets: ["KodmozScreen"])
    ],
    targets: [
        // CGVirtualDisplay, macOS'un belgelenmemiş ama yıllardır kullanılan
        // sanal ekran API'si. Objective-C köprüsü sayesinde sınıflar yoksa
        // uygulama çökmez, aynalama moduna düşer.
        .target(
            name: "CVirtualDisplay",
            path: "Sources/CVirtualDisplay"
        ),
        .executableTarget(
            name: "KodmozScreen",
            dependencies: ["CVirtualDisplay"],
            path: "Sources/KodmozScreen",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Network"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
