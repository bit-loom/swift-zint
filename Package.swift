// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-zint",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "SwiftZint",
            targets: ["SwiftZint"]
        ),
    ],
    targets: [
        .target(
            name: "CZint",
            path: "Sources/CZint",
            exclude: [
                "zint/backend/tests",
                "zint/backend/tools",
                "zint/backend/fonts",
                "zint/backend/CMakeLists.txt",
                "zint/backend/Makefile.mingw",
                "zint/backend/libzint.rc",
                "zint/backend/dllversion.c",
                "zint/backend/png.c",
                "zint/backend/README",
                "zint/UPSTREAM-LICENSE",
            ],
            sources: ["zint/backend"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("zint/backend"),
                .define("ZINT_NO_PNG"),
                .unsafeFlags(["-Wno-unused-parameter", "-Wno-sign-compare"]),
            ]
        ),
        .target(
            name: "SwiftZint",
            dependencies: ["CZint"]
        ),
        .testTarget(
            name: "SwiftZintTests",
            dependencies: ["SwiftZint"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
