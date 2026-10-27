// swift-tools-version: 6.0
// PSolitaire — Swift 네이티브 재작성(SwiftUI + Canvas).
// PSolitaireKit: 창 없이 테스트 가능한 규칙 엔진 / PSolitaire: SwiftUI 앱(실행 파일)
import PackageDescription

let package = Package(
    name: "PSolitaire",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PSolitaireKit", targets: ["PSolitaireKit"]),
        .executable(name: "PSolitaire", targets: ["PSolitaire"]),
    ],
    targets: [
        // Swift 5 언어 모드: 앱이 단일 스레드(MainActor)라 엄격 동시성 검사가 소음만 늘린다.
        .target(name: "PSolitaireKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PSolitaire", dependencies: ["PSolitaireKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "PSolitaireKitTests", dependencies: ["PSolitaireKit"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
