import BatonKit
import Observation

/// スリープ時の切断と、復帰時の再接続を行う（仕様書 7、MVP の扱い）。
///
/// - ユーザーが離れるとき（スリープに入る直前、画面をロックしたとき）：
///   この Mac に接続中の登録機器を切断し、「離れる前に接続していた機器」として記録する
/// - ユーザーが戻ってきたとき（ロックを解除したとき、画面が点いたとき）：
///   記録した機器のうち、まだ接続していないものに接続を試す。記録は消す
/// - 再接続に失敗したら（他の端末で使用中など）、あきらめる。エラーメッセージは出さない
///
/// MVP では他の端末に問い合わせない。他の端末で使用中なら接続が失敗するので、それであきらめる（docs/mvp.md）。
@MainActor
@Observable
final class SleepHandler {
    /// 離れる前にこの Mac が接続していた機器（戻ってきたら再接続する）
    private(set) var devicesToReconnect: Set<BluetoothAddress> = []

    @ObservationIgnored private let deviceStore: DeviceStore
    @ObservationIgnored private let power: any PowerEventService

    init(power: any PowerEventService, deviceStore: DeviceStore) {
        self.power = power
        self.deviceStore = deviceStore

        power.onUserLeaving = { [weak self] in
            Task { await self?.handleUserLeaving() }
        }
        power.onUserReturned = { [weak self] in
            Task { await self?.handleUserReturned() }
        }
    }

    /// ユーザーが離れるときの処理：接続中の登録機器を切断し、記録する。
    /// スリープまでの時間が短いので、すべての機器の切断を同時に始める。
    /// 画面のロックとスリープが続けて起きて2回呼ばれても、2回目は切断する機器がないので何もしない
    func handleUserLeaving() async {
        let connected = deviceStore.registeredDevices
            .map(\.address)
            .filter { deviceStore.isConnected($0) }
        guard !connected.isEmpty else {
            return
        }
        // 切断より先に記録する（切断の途中でスリープに入っても、復帰したら再接続できるように）
        devicesToReconnect.formUnion(connected)

        await withTaskGroup(of: Void.self) { group in
            for address in connected {
                group.addTask { await self.deviceStore.disconnect(address) }
            }
        }
    }

    /// ユーザーが戻ってきたときの処理：記録した機器に接続を試す
    func handleUserReturned() async {
        let targets = devicesToReconnect
        // 先に記録を消す（画面の通知とシステムの通知が重なって2回呼ばれても、2回目は何もしないように）
        devicesToReconnect.removeAll()

        for address in targets where !deviceStore.isConnected(address) {
            // スリープ中にヘッドホンの側からつないできた場合は、すでに接続しているので何もしない
            await deviceStore.connect(address, reportsErrors: false)
        }
    }
}
