// swift-tools-version:5.9
import PackageDescription
import Foundation

// Встраиваем Info.plist в бинарник, чтобы у приложения был bundle identifier
// даже при запуске из Xcode или через `swift run` (без сборки .app).
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

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
            dependencies: ["KnjigeCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageRoot)/Assets/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "KnjigeCoreTests",
            dependencies: ["KnjigeCore"]
        )
    ]
)
