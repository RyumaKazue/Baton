import Foundation

/// macOS の Bluetooth の仕組み（bluetoothd）が起動し直したことを、CoreBluetooth の状態の変化から見分ける（#51）。
///
/// 電池が切れかけて深いスリープ（ハイバネート）に入り、充電して起きると、bluetoothd が一度終わって起動し直す。
/// すると、動いていた Baton の中の IOBluetooth / CoreBluetooth が機器の情報を正しく持てなくなり、
/// 通知も isConnected() も正しく取れなくなる。直すには Baton を起動し直すしかない（2026-10-14 の調査）。
///
/// CoreBluetooth の状態は、bluetoothd が起動し直すと次の順で変わる（`sudo killall bluetoothd` で確認）。
/// 1. resetting：bluetoothd との接続が切れた。この時点では、新しい bluetoothd はまだ起動していないことがある
/// 2. poweredOn：新しい bluetoothd とつながり、Bluetooth が使えるようになった → ここで起動し直す
///
/// CoreBluetooth を使わない、ただの判断なので、BatonKit に置いてテストする。
public struct BluetoothDaemonRestartDetector: Sendable {
    /// CoreBluetooth の状態のうち、判断に使うもの
    public enum State: Sendable {
        /// bluetoothd との接続が切れた（CBManagerState.resetting）
        case resetting
        /// Bluetooth が使える（CBManagerState.poweredOn）
        case poweredOn
        /// それ以外（オフ、権限なし など）
        case other
    }

    /// 起動してから、この時間は起動し直さない（起動し直しを繰り返さないための安全弁）
    public let minimumUptime: TimeInterval

    /// resetting を受け取ったか（この後 poweredOn になったら起動し直す）
    private var sawReset = false

    public init(minimumUptime: TimeInterval = 30) {
        self.minimumUptime = minimumUptime
    }

    /// 状態の変化を受け取り、Baton を起動し直すべきかを答える
    /// - Parameter uptime: Baton が起動してからの時間
    public mutating func shouldRelaunch(on state: State, uptime: TimeInterval) -> Bool {
        switch state {
        case .resetting:
            sawReset = true
            return false
        case .poweredOn:
            guard sawReset else {
                return false  // ふつうの起動や、ユーザーが Bluetooth をオフ → オンにしたとき
            }
            sawReset = false
            return uptime >= minimumUptime
        case .other:
            // 起動し直した後にユーザーが Bluetooth をオフにした場合なども、覚えたまま poweredOn を待つ
            return false
        }
    }
}
