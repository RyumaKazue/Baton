/// 偽物の PowerEventService。テストで、ユーザーが離れた・戻ってきたことを再現するために使う。
@MainActor
final class MockPowerEventService: PowerEventService {
    var onUserLeaving: (() -> Void)?
    var onUserReturned: (() -> Void)?

    /// ユーザーが離れた（スリープに入る直前、画面をロックした）ことを再現する
    func simulateUserLeaving() {
        onUserLeaving?()
    }

    /// ユーザーが戻ってきた（ロックを解除した、画面が点いた）ことを再現する
    func simulateUserReturned() {
        onUserReturned?()
    }
}
