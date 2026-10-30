import Combine
import Foundation

enum PanelEdge: String, CaseIterable, Identifiable {
    case top, right, bottom, left

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var isVertical: Bool { self == .left || self == .right }
    var collapseSymbol: String {
        switch self {
        case .top: "arrow.up.to.line"
        case .right: "arrow.right.to.line"
        case .bottom: "arrow.down.to.line"
        case .left: "arrow.left.to.line"
        }
    }
}

/// One preference shared by History and Paste Stack; contains no clipboard data.
@MainActor
final class PanelPreferences: ObservableObject {
    static let edgeKey = "panelPresentation.edge"
    @Published private(set) var edge: PanelEdge
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: Self.edgeKey).flatMap(PanelEdge.init(rawValue:)) ?? .top
    }

    func setEdge(_ edge: PanelEdge) {
        guard self.edge != edge else { return }
        defaults.set(edge.rawValue, forKey: Self.edgeKey)
        self.edge = edge
    }
}
