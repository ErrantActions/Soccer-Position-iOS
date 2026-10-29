// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoachCore",
    products: [.library(name: "CoachCore", targets: ["CoachCore"])],
    targets: [
        .target(
            name: "CoachCore",
            path: "App",
            exclude: [
                "CoachAIApp.swift", "CoachView.swift", "PitchView.swift", "PositioningIntelligence.swift",
                "Info.plist", "CoachAI.entitlements", "PrivacyInfo.xcprivacy",
            ],
            sources: ["Positioning.swift", "CoachingLayout.swift", "RouteDrawing.swift", "AIPositioning.swift"]
        ),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"], path: "Tests"),
    ]
)
