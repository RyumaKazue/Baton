/// ユーザーが Mac から離れた・戻ってきた、という出来事を知らせるサービスの約束ごと。
///
/// macOS からはいろいろな通知（スリープ、画面のロック、画面の点灯など）が届くが、
/// Baton に必要なのは「離れた」「戻ってきた」の2つだけなので、それにまとめて知らせる。
/// 離れたときは、設定で切断するかを選べるように、理由（LeaveReason）も一緒に知らせる。
/// テストでは、偽物（MockPowerEventService）に差し替えて再現する。
@MainActor
protocol PowerEventService: AnyObject {
    /// ユーザーが Mac から離れるときに、理由と一緒に呼ばれる（画面をロックしたとき、スリープに入る直前、画面が消えたとき）。
    /// スリープの場合、実際にスリープするまでは数秒しかない（docs/spikes/iobluetooth.md 4.4）
    var onUserLeaving: ((LeaveReason) -> Void)? { get set }

    /// ユーザーが戻ってきたときに呼ばれる（ロックを解除したとき、ロックされていない状態で画面が点いたとき）。
    /// ダークウェイク（画面を消したまま一時的に起きる状態）や、ロック画面のままでは呼ばれない（docs/spikes/sleep-reconnect.md 5）
    var onUserReturned: (() -> Void)? { get set }
}

/// ユーザーが離れた理由。どの理由で切断するかは、設定（AppSettings）で選べる
enum LeaveReason: CustomStringConvertible {
    /// 画面をロックした（電源ボタン、⌃⌘Q、ロックまでの時間が過ぎた など）
    case screenLock
    /// スリープに入る直前（メニューの「スリープ」、ふたを閉じる など）
    case sleep
    /// 画面が消えた（ディスプレイのスリープ）
    case displaySleep

    /// ログに出す名前
    var description: String {
        switch self {
        case .screenLock: "ロック"
        case .sleep: "スリープ"
        case .displaySleep: "画面の消灯"
        }
    }
}
