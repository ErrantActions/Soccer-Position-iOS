import SwiftUI

struct WorkspacePicker<Workspace: CaseIterable & Hashable & RawRepresentable>: View where Workspace.RawValue == String {
    @Binding var selection: Workspace
    let symbol: (Workspace) -> String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                                 count: CoachingLayout.toolColumns(width: availableWidth, largeText: typeSize.isAccessibilitySize)), spacing: 8) {
            ForEach(Array(Workspace.allCases), id: \.self) { workspace in
                Button { selection = workspace } label: {
                    Label(workspace.rawValue, systemImage: symbol(workspace))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                        .foregroundStyle(selection == workspace ? CoachPalette.ink : .white)
                        .background(selection == workspace ? CoachPalette.lime : CoachPalette.surface,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(workspace.rawValue) tools")
                .accessibilityAddTraits(selection == workspace ? .isSelected : [])
                .accessibilityIdentifier("coach.workspace.\(workspace.rawValue.lowercased())")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool groups")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}

struct ExpandableToolGroup<Content: View>: View {
    let title: String
    let symbol: String
    @Binding var expanded: Bool
    let content: Content

    init(_ title: String, systemImage: String, expanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        symbol = systemImage
        _expanded = expanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(.white)
                .coachCard()
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content }
        }
    }
}
