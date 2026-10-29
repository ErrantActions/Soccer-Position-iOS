import XCTest
#if canImport(CoachAI)
@testable import CoachAI
#else
@testable import CoachCore
#endif

final class ControlNavigationTests: XCTestCase {
    func testDefaultShowsCoachingWithoutExpandingOptionalSettings() {
        let navigation = ControlNavigation()
        XCTAssertEqual(navigation.workspace, .coach)
        XCTAssertEqual(navigation.anchor, "coach.workspace")
        XCTAssertFalse(navigation.routesExpanded)
        XCTAssertFalse(navigation.analysisExpanded)
    }

    func testEveryMainWorkspaceHasAVisibleNameSymbolAndDescription() {
        XCTAssertEqual(CoachWorkspace.allCases.count, 4)
        XCTAssertEqual(Set(CoachWorkspace.allCases.map(\.rawValue)).count, 4)
        for workspace in CoachWorkspace.allCases {
            XCTAssertFalse(workspace.symbol.isEmpty)
            XCTAssertFalse(workspace.summary.isEmpty)
        }
    }

    func testEveryDestinationMapsToItsTaskAndStableScrollAnchor() {
        let expected: [(CoachDestination, CoachWorkspace, String)] = [
            (.coach, .coach, "coach.workspace"),
            (.routes, .coach, "coach.routes"),
            (.analysis, .coach, "coach.analysis"),
            (.playbook, .plays, "coach.library"),
            (.sequence, .plays, "coach.sequence"),
            (.practice, .practice, "coach.practice"),
            (.presentation, .present, "coach.presentation"),
        ]
        XCTAssertEqual(expected.count, CoachDestination.allCases.count)
        for (destination, workspace, anchor) in expected {
            var navigation = ControlNavigation()
            navigation.reveal(destination)
            XCTAssertEqual(navigation.workspace, workspace)
            XCTAssertEqual(navigation.anchor, anchor)
        }
    }

    func testNativeDrawingAndAnalysisRevealTheirOptionalPanels() {
        var navigation = ControlNavigation()
        navigation.select(.present)
        navigation.reveal(.routes)
        XCTAssertEqual(navigation.workspace, .coach)
        XCTAssertTrue(navigation.routesExpanded)
        XCTAssertFalse(navigation.analysisExpanded)
        navigation.reveal(.analysis)
        XCTAssertTrue(navigation.analysisExpanded)
        XCTAssertTrue(navigation.routesExpanded)
    }

    func testSwitchingGroupsRetainsDisclosureChoicesInsteadOfResettingTools() {
        var navigation = ControlNavigation()
        navigation.routesExpanded = true
        navigation.analysisExpanded = true
        for workspace in CoachWorkspace.allCases {
            navigation.select(workspace)
            XCTAssertEqual(navigation.workspace, workspace)
            XCTAssertEqual(navigation.anchor, "coach.workspace")
            XCTAssertTrue(navigation.routesExpanded)
            XCTAssertTrue(navigation.analysisExpanded)
        }
    }

    func testRepeatedNativeActionCanRefocusAnAlreadySelectedGroup() {
        var navigation = ControlNavigation()
        navigation.reveal(.routes)
        let first = navigation.revision
        navigation.reveal(.routes)
        XCTAssertGreaterThan(navigation.revision, first)
        XCTAssertEqual(navigation.anchor, "coach.routes")
    }

    func testCompactNativeDrawingRefocusesPitchRatherThanScrollingItAway() {
        var navigation = ControlNavigation()
        navigation.reveal(.routes)
        XCTAssertEqual(navigation.compactAnchor, "coach.pitch")
        navigation.reveal(.presentation)
        XCTAssertEqual(navigation.compactAnchor, "coach.presentation")
        navigation.select(.coach)
        XCTAssertEqual(navigation.compactAnchor, "coach.workspace")
    }

    func testPickerReflowsForNarrowPanesAndAccessibilityText() {
        XCTAssertEqual(CoachingLayout.toolColumns(width: 196, largeText: false), 1)
        XCTAssertEqual(CoachingLayout.toolColumns(width: 279, largeText: false), 1)
        XCTAssertEqual(CoachingLayout.toolColumns(width: 280, largeText: false), 2)
        XCTAssertEqual(CoachingLayout.toolColumns(width: 390, largeText: false), 2)
        XCTAssertEqual(CoachingLayout.toolColumns(width: 800, largeText: true), 1)
    }

    func testAuthoringGroupsKeepDestructiveSetupSeparateFromRoutineEditing() {
        XCTAssertEqual(DesignerWorkspace.allCases, [.phases, .players, .setup, .details])
        for workspace in DesignerWorkspace.allCases { XCTAssertFalse(workspace.symbol.isEmpty) }
    }

    func testControlGroupingDoesNotChangeDuoOrderingOrFixedPitchPolicy() {
        let layout = CoachingLayout.resolve(size: .init(width: 650, height: 800), division: nil, duoDisplay: true)
        XCTAssertEqual(layout.controlSections, [.routes, .ai, .role])
        XCTAssertNotNil(layout.coachPane)
        let originalPitch = layout.pitchPane
        var navigation = ControlNavigation()
        for destination in CoachDestination.allCases {
            navigation.reveal(destination)
            let current = CoachingLayout.resolve(size: .init(width: 650, height: 800), division: nil, duoDisplay: true)
            XCTAssertEqual(current.pitchPane, originalPitch)
        }
    }
}
