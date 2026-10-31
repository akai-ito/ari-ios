import AriKit

/// A button on a card, as the Desk draws it: answering sends its label.
struct CardButton: Hashable, Identifiable {
    let label: String
    /// The one that goes ahead, filled like Send.
    var acts = false

    var id: String { label }
}

// The one place the Desk's views read a card's buttons and state from: each card carries its own
// buttons, whether words work as an answer, and a `working` state while the box acts.
extension DeskCard {
    /// The buttons to draw, in order. A draft's and a times card's are their own (Change…, Draft
    /// it), so the server sends them none.
    var buttons: [CardButton] { options.map { CardButton(label: $0.label, acts: $0.acts) } }

    /// Whether the box is acting on your answer, such as redrafting: the buttons wait meanwhile.
    var isWorking: Bool { state == .working }

    /// Whether words work as an answer too.
    var takesText: Bool { allowsText }
}
