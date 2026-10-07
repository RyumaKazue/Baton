/// ユーザーが Mac から離れた・戻ってきた、という出来事を知らせるサービスの約束ごと。
///
/// macOS からはいろいろな通知（スリープ、画面のロック、画面の点灯など）が届くが、
/// Baton に必要なのは「離れた」「戻ってきた」の2つだけなので、それにまとめて知らせる。
/// テストでは、偽物（MockPowerEventService）に差し替えて再現する。
@MainActor
protocol PowerEventService: AnyObject {
    /// ユーザーが Mac から離れるときに呼ばれる（スリープに入る直前、画面をロックしたとき）。
    /// スリープの場合、実際にスリープするまでは数秒しかない（docs/spikes/iobluetooth.md 4.4）
    var onUserLeaving: (() -> Void)? { get set }

    /// ユーザーが戻ってきたときに呼ばれる（ロックを解除したとき、ロックされていない状態で画面が点いたとき）。
    /// ダークウェイク（画面を消したまま一時的に起きる状態）や、ロック画面のままでは呼ばれない（docs/spikes/sleep-reconnect.md 5）
    var onUserReturned: (() -> Void)? { get set }
}
