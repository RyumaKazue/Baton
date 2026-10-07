/// 偽物の PowerEventService。テストで、スリープや復帰を再現するために使う。
@MainActor
final class MockPowerEventService: PowerEventService {
    var onWillSleep: (() -> Void)?
    var onUserReturned: (() -> Void)?

    /// スリープに入る直前の通知を再現する
    func simulateWillSleep() {
        onWillSleep?()
    }

    /// ユーザーが戻ってきた（画面が点いた）通知を再現する
    func simulateUserReturned() {
        onUserReturned?()
    }
}
