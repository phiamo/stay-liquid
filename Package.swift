// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StayLiquid",
    platforms: [.iOS(.v18)],
    products: [
        .library(
            name: "StayLiquid",
            targets: ["TabsBarPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "TabsBarPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/TabsBarPlugin")
    ]
)
