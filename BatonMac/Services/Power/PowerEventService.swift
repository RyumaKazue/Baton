/// スリープ・復帰に関する出来事を知らせるサービスの約束ごと。
///
/// macOS からはいろいろな通知が届くが、Baton に必要なのは次の2つだけなので、それにまとめて知らせる。
/// テストでは、偽物（MockPowerEventService）に差し替えて、スリープや復帰を再現する。
@MainActor
protocol PowerEventService: AnyObject {
    /// Mac がスリープに入る直前に呼ばれる。
    /// 実際にスリープするまでは数秒しかない（docs/spikes/iobluetooth.md 4.4）
    var onWillSleep: (() -> Void)? { get set }

    /// ユーザーが戻ってきた（画面が点いた）ときに呼ばれる。
    /// ダークウェイク（画面を消したまま一時的に起きる状態）では呼ばれない（docs/spikes/sleep-reconnect.md 5）
    var onUserReturned: (() -> Void)? { get set }
}
