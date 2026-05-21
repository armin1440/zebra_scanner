// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zebra_handheld_scanner",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "zebra-handheld-scanner", targets: ["zebra_handheld_scanner"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "zebra_handheld_scanner",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
