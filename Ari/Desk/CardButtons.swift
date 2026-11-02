import AriKit

// The one place the Desk's views read a card's state from: each card carries its own buttons (its
// `options`), whether words work as an answer (`allowsText`), and a `working` state while the box
// acts. A draft's and a times card's own buttons are the app's (Change…, Open in Mail, Draft it);
// what the server sends a draft, such as Drop it, sits quietly beside them.
extension DeskCard {
    /// Whether the box is acting on your answer, such as redrafting: the buttons wait meanwhile.
    var isWorking: Bool { state == .working }

    /// While the box works on it: the option you tapped or the words you wrote, to show as your
    /// answer. Times are shown ticked instead.
    var answerWords: String? {
        guard isWorking else { return nil }
        return answer?.option ?? answer?.text
    }
}
