import BatonKit
import Observation
import os

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
            Logger.sleep.notice("離れる：切断する機器なし")
            return
        }
        Logger.sleep.notice("離れる：\(connected.map(\.rawValue).joined(separator: "、"), privacy: .public) を切断して記録する")
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
        guard !targets.isEmpty else {
            Logger.sleep.debug("戻ってきた：再接続する機器なし")
            return
        }
        Logger.sleep.notice("戻ってきた：\(targets.map(\.rawValue).joined(separator: "、"), privacy: .public) を再接続する")

        for address in targets {
            // スリープ中にヘッドホンの側からつないできた場合は、すでに接続しているので何もしない
            guard !deviceStore.isConnected(address) else {
                Logger.sleep.notice("すでに接続済みなので再接続しない：\(address, privacy: .public)")
                continue
            }
            await deviceStore.connect(address, reportsErrors: false)
        }
    }
}
