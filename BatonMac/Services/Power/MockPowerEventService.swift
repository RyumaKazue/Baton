/// 偽物の PowerEventService。テストで、ユーザーが離れた・戻ってきたことを再現するために使う。
@MainActor
final class MockPowerEventService: PowerEventService {
    var onUserLeaving: ((LeaveReason) -> Void)?
    var onUserReturned: (() -> Void)?

    /// ユーザーが離れた（画面をロックした、スリープに入る直前、画面が消えた）ことを再現する
    func simulateUserLeaving(_ reason: LeaveReason) {
        onUserLeaving?(reason)
    }

    /// ユーザーが戻ってきた（ロックを解除した、画面が点いた）ことを再現する
    func simulateUserReturned() {
        onUserReturned?()
    }
}
