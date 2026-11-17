// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Knjige",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Knjige", targets: ["Knjige"])
    ],
    targets: [
        .target(name: "KnjigeCore"),
        .executableTarget(
            name: "Knjige",
            dependencies: ["KnjigeCore"]
        ),
        .testTarget(
            name: "KnjigeCoreTests",
            dependencies: ["KnjigeCore"]
        )
    ]
)
