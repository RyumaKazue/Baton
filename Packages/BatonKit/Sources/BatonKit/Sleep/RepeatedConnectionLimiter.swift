import Foundation

/// 離れている間につないできた機器を切るときの安全弁。
///
/// ヘッドホンによっては、切られても何度も Mac につなぎに来るかもしれない。そのたびに寝ている Mac が起きて、
/// Mac とヘッドホンの電池が減り続けないように、同じ機器を切るのは「直近の5分間に3回まで」とし、それを超えたら「切らない」と答える
/// （切らなければ機器はつながったままになり、また来ることはないので、繰り返しが止まる）。
/// 5分より前に切った回は数えないので、時間を置いてまた来たときは、また切ってよいと答える
/// （docs/spikes/sleep-reconnect.md 8。EDIFIER は2回で iPhone に移った）。
///
/// 時刻は呼ぶ側が渡す。テストでは、本当に待たずに時間を進められる。
public struct RepeatedConnectionLimiter: Sendable {
    /// 数える時間の幅（window）の中で、この回数まで切ってよい
    public let maxDisconnections: Int
    /// 数える時間の幅。これより前に切った回は数えない
    public let window: TimeInterval

    /// 機器ごとの、切った時刻
    private var history: [BluetoothAddress: [Date]] = [:]

    public init(maxDisconnections: Int = 3, window: TimeInterval = 5 * 60) {
        self.maxDisconnections = maxDisconnections
        self.window = window
    }

    /// 今その機器を切ってよいかを答える。よければ、切ったものとして記録する
    public mutating func allowsDisconnect(_ address: BluetoothAddress, at now: Date) -> Bool {
        let recent = (history[address] ?? []).filter { now.timeIntervalSince($0) < window }
        guard recent.count < maxDisconnections else {
            history[address] = recent
            return false
        }
        history[address] = recent + [now]
        return true
    }

    /// 記録を消す（戻ってきたとき。次に離れたときは、また0から数える）
    public mutating func reset() {
        history.removeAll()
    }
}
