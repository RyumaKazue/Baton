import BatonKit
import Foundation
import Observation
import os

/// スリープ時の切断と、復帰時の再接続を行う（仕様書 7、MVP の扱い）。
///
/// - ユーザーが離れるとき（画面をロックしたとき、スリープに入る直前、画面が消えたとき）：
///   その理由で切断する設定（AppSettings）なら、「離れている間」にして、この Mac に接続中の登録機器を切断し、
///   「離れる前に接続していた機器」として記録する。設定がオフなら何もしない
/// - 離れている間に登録機器がつないできたとき（ヘッドホンの電源を入れ直した など）：
///   すぐ切断し、戻ってきたら再接続する機器として記録する。寝ている Mac でも、接続でダークウェイクした
///   数秒の間に切断できる（docs/spikes/sleep-reconnect.md 8）
/// - ユーザーが戻ってきたとき（ロックを解除したとき、画面が点いたとき）：
///   「離れている間」を終わりにして、記録した機器のうち、まだ接続していないものに接続を試す。記録は消す
/// - 再接続に失敗したら（他の端末で使用中など）、あきらめる。エラーメッセージは出さない
///
/// MVP では他の端末に問い合わせない。他の端末で使用中なら接続が失敗するので、それであきらめる（docs/mvp.md）。
@MainActor
@Observable
final class SleepHandler {
    /// 離れる前、または離れている間にこの Mac から切断した機器（戻ってきたら再接続する）
    private(set) var devicesToReconnect: Set<BluetoothAddress> = []
    /// 離れている間か（設定がオンのきっかけで離れてから、戻ってくるまで）。
    /// 離れている間に登録機器がつないできたら切断する
    private(set) var isAway = false

    @ObservationIgnored private let deviceStore: DeviceStore
    @ObservationIgnored private let power: any PowerEventService
    @ObservationIgnored private let settings: AppSettings
    /// 今の時刻。テストでは、時刻を決めた関数を渡す
    @ObservationIgnored private let now: () -> Date
    /// 安全弁：同じ機器が何度もつないでくるときに、切るのをやめる
    @ObservationIgnored private var limiter = RepeatedConnectionLimiter()

    init(
        power: any PowerEventService,
        deviceStore: DeviceStore,
        settings: AppSettings,
        now: @escaping () -> Date = Date.init
    ) {
        self.power = power
        self.deviceStore = deviceStore
        self.settings = settings
        self.now = now

        power.onUserLeaving = { [weak self] reason in
            Task { await self?.handleUserLeaving(reason: reason) }
        }
        power.onUserReturned = { [weak self] in
            Task { await self?.handleUserReturned() }
        }
        // DeviceStore に「機器がつながったら呼ぶ処理」を渡す（依存は SleepHandler → DeviceStore の一方向のまま）
        deviceStore.onDeviceConnected = { [weak self] address in
            self?.handleDeviceConnected(address)
        }
    }

    /// ユーザーが離れるときの処理：その理由で切断する設定なら、接続中の登録機器を切断し、記録する。
    /// スリープまでの時間が短いので、すべての機器の切断を同時に始める。
    /// 画面のロックとスリープが続けて起きて2回呼ばれても、2回目は切断する機器がないので何もしない
    func handleUserLeaving(reason: LeaveReason) async {
        // 設定がオフなら、切断も記録もしない（記録がないので、戻ってきたときの再接続もしない）
        guard settings.disconnects(on: reason) else {
            Logger.sleep.notice("離れる（\(reason, privacy: .public)）：設定がオフなので切断しない")
            return
        }
        // 切断する機器がなくても「離れている間」にする（ヘッドホンの電源を切ってから離れ、後で入れ直した場合も守るため）
        isAway = true
        let connected = deviceStore.registeredDevices
            .map(\.address)
            .filter { deviceStore.isConnected($0) }
        guard !connected.isEmpty else {
            Logger.sleep.notice("離れる（\(reason, privacy: .public)）：切断する機器なし")
            return
        }
        Logger.sleep.notice("離れる（\(reason, privacy: .public)）：\(connected.map(\.rawValue).joined(separator: "、"), privacy: .public) を切断して記録する")
        // 切断より先に記録する（切断の途中でスリープに入っても、復帰したら再接続できるように）
        devicesToReconnect.formUnion(connected)

        await withTaskGroup(of: Void.self) { group in
            for address in connected {
                group.addTask { await self.deviceStore.disconnect(address) }
            }
        }
    }

    /// 離れている間に機器がつないできたときの処理：登録機器なら切断し、戻ってきたら再接続する機器として記録する。
    /// 切るかどうかは、通知が届いたその場で決める（後回しにすると、離れる前につながった機器まで、
    /// 判断を待つ間に始まった「離れている間」として扱ってしまうため）。切断だけを後で行う
    private func handleDeviceConnected(_ address: BluetoothAddress) {
        guard isAway, deviceStore.isRegistered(address) else {
            return
        }
        guard limiter.allowsDisconnect(address, at: now()) else {
            Logger.sleep.notice("離れている間に何度もつないでくるので、切るのをやめる：\(address, privacy: .public)")
            return
        }
        Logger.sleep.notice("離れている間につないできたので切断する：\(address, privacy: .public)")
        // 戻ってきたら再接続する（戻る前にヘッドホンの電源を先に入れた場合のため）
        devicesToReconnect.insert(address)
        Task { await deviceStore.disconnect(address) }
    }

    /// ユーザーが戻ってきたときの処理：「離れている間」を終わりにして、記録した機器に接続を試す
    func handleUserReturned() async {
        // 再接続より先に終わりにする（再接続でつながったときに、切断してしまわないように）
        isAway = false
        limiter.reset()
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
