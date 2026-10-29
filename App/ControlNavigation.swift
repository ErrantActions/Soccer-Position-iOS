enum CoachWorkspace: String, CaseIterable {
    case coach = "Coach", plays = "Plays", practice = "Practice", present = "Present"
    var symbol: String {
        switch self { case .coach: "soccerball"; case .plays: "books.vertical"; case .practice: "scope"; case .present: "tv" }
    }
    var summary: String {
        switch self {
        case .coach: "Scene, positions, drawing and optional on-device AI."
        case .plays: "Your library, youth teams and captured sequences."
        case .practice: "Place your player, then check the teaching guide."
        case .present: "External field, TV readability and spoken coaching."
        }
    }
}

enum CoachDestination: CaseIterable, Equatable {
    case coach, routes, analysis, playbook, sequence, practice, presentation
    var workspace: CoachWorkspace {
        switch self {
        case .coach, .routes, .analysis: .coach
        case .playbook, .sequence: .plays
        case .practice: .practice
        case .presentation: .present
        }
    }
    var anchor: String {
        switch self {
        case .coach: "coach.workspace"
        case .routes: "coach.routes"
        case .analysis: "coach.analysis"
        case .playbook: "coach.library"
        case .sequence: "coach.sequence"
        case .practice: "coach.practice"
        case .presentation: "coach.presentation"
        }
    }
}

struct ControlNavigation {
    private(set) var workspace: CoachWorkspace = .coach
    private(set) var anchor = "coach.workspace"
    private(set) var revision = 0
    var routesExpanded = false
    var analysisExpanded = false
    var compactAnchor: String { anchor == CoachDestination.routes.anchor ? "coach.pitch" : anchor }

    mutating func select(_ workspace: CoachWorkspace) {
        self.workspace = workspace
        anchor = "coach.workspace"
        revision += 1
    }
    mutating func reveal(_ destination: CoachDestination) {
        workspace = destination.workspace
        anchor = destination.anchor
        if destination == .routes { routesExpanded = true }
        if destination == .analysis { analysisExpanded = true }
        revision += 1
    }
}

enum DesignerWorkspace: String, CaseIterable {
    case phases = "Phases", players = "Players", setup = "Setup", details = "Details"
    var symbol: String {
        switch self { case .phases: "rectangle.stack"; case .players: "person.3"; case .setup: "soccerball"; case .details: "square.and.pencil" }
    }
}
