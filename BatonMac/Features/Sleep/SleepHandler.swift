import BatonKit
import Foundation
import Observation
import os

/// スリープ時の切断と、復帰時の再接続を行う（仕様書 7、MVP の扱い）。
///
/// - ユーザーが離れるとき（画面をロックしたとき、スリープに入る直前、画面が消えたとき）：
///   その理由で切断する設定（AppSettings）なら、「離れている間」にして、この Mac に接続中の登録機器を切断し、
///   「離れる前に接続していた機器」として記録する。設定がオフなら何もしない
/// - ただし、ロックと画面の消灯のときにヘッドホンから音が出ていれば（「再生中は切断しない」がオンのとき）、
///   切断せずに「音が止まるのを待っている」にする。音が止まって一定時間たったら、そこで切断する。
///   スリープでは、再生中でも切断する（Mac が寝ると音は止まるため）
/// - 離れている間に登録機器がつないできたとき（ヘッドホンの電源を入れ直した など）：
///   すぐ切断し、戻ってきたら再接続する機器として記録する。寝ている Mac でも、接続でダークウェイクした
///   数秒の間に切断できる（docs/spikes/sleep-reconnect.md 8）
/// - ユーザーが戻ってきたとき（ロックを解除したとき、画面が点いたとき）：
///   「使っている」に戻して、記録した機器のうち、まだ接続していないものに接続を試す。記録は消す
/// - 再接続に失敗したら（他の端末で使用中など）、あきらめる。エラーメッセージは出さない
///
/// MVP では他の端末に問い合わせない。他の端末で使用中なら接続が失敗するので、それであきらめる（docs/mvp.md）。
@MainActor
@Observable
final class SleepHandler {
    /// ユーザーがいるか・離れているか
    enum Presence: Equatable {
        /// 使っている（ふだん）
        case present
        /// 再生中にロック（または画面の消灯）した。音が止まるのを待っている。まだ切断していない
        case waitingForSilence
        /// 離れている間（設定がオンのきっかけで離れて切断してから、戻ってくるまで）。つないできた登録機器は切断する
        case away
    }

    /// 今の状態
    private(set) var presence: Presence = .present
    /// 離れる前、または離れている間にこの Mac から切断した機器（戻ってきたら再接続する）
    private(set) var devicesToReconnect: Set<BluetoothAddress> = []

    /// 離れている間か
    var isAway: Bool {
        presence == .away
    }

    @ObservationIgnored private let deviceStore: DeviceStore
    @ObservationIgnored private let power: any PowerEventService
    @ObservationIgnored private let settings: AppSettings
    /// 今の時刻。テストでは、時刻を決めた関数を渡す
    @ObservationIgnored private let now: () -> Date
    /// 安全弁：同じ機器が何度もつないでくるときに、切るのをやめる
    @ObservationIgnored private var limiter = RepeatedConnectionLimiter()
    /// 音が止まるのを見張る処理（音が止まるのを待っている間だけ動く）
    @ObservationIgnored private var silenceWatcher: Task<Void, Never>?
    /// 音が出ているかを読む間隔
    @ObservationIgnored private let silenceCheckInterval: Duration
    /// 音が出ていないのが、この回数続いたら切断する（間隔2秒なら15回で約30秒）
    @ObservationIgnored private let silentChecksBeforeLeaving: Int

    /// - Parameters:
    ///   - silenceCheckInterval: 音が出ているかを読む間隔。テストでは 0 にする
    ///   - silentChecksBeforeLeaving: 音が出ていないのが何回続いたら切断するか。曲の間や短い一時停止で切れないように、少し待つ
    init(
        power: any PowerEventService,
        deviceStore: DeviceStore,
        settings: AppSettings,
        now: @escaping () -> Date = Date.init,
        silenceCheckInterval: Duration = .seconds(2),
        silentChecksBeforeLeaving: Int = 15
    ) {
        self.power = power
        self.deviceStore = deviceStore
        self.settings = settings
        self.now = now
        self.silenceCheckInterval = silenceCheckInterval
        self.silentChecksBeforeLeaving = silentChecksBeforeLeaving

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
    /// ロックと画面の消灯のときに音が出ていれば、切断せずに、音が止まるのを待つ。
    /// 画面のロックとスリープが続けて起きて2回呼ばれても、2回目は切断する機器がないので何もしない
    func handleUserLeaving(reason: LeaveReason) async {
        // 設定がオフなら、切断も記録もしない（記録がないので、戻ってきたときの再接続もしない）
        guard settings.disconnects(on: reason) else {
            Logger.sleep.notice("離れる（\(reason, privacy: .public)）：設定がオフなので切断しない")
            return
        }
        // 再生中なら、ロックと画面の消灯では切断しない（スリープでは切断する。Mac が寝ると音は止まるため）
        if reason != .sleep, settings.keepsConnectionWhilePlaying, presence != .away {
            let playing = connectedRegisteredDevices().filter { deviceStore.isPlaying($0) }
            if !playing.isEmpty {
                Logger.sleep.notice("離れる（\(reason, privacy: .public)）：\(playing.map(\.rawValue).joined(separator: "、"), privacy: .public) から音が出ているので切断せず、止まるのを待つ")
                startWaitingForSilence()
                return
            }
        }
        await leave(because: "\(reason)")
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

    /// ユーザーが戻ってきたときの処理：「使っている」に戻して、記録した機器に接続を試す
    func handleUserReturned() async {
        stopWaitingForSilence()
        // 再接続より先に戻す（再接続でつながったときに、切断してしまわないように）
        presence = .present
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

    // MARK: - 補助

    /// 離れる：「離れている間」にして、接続中の登録機器を切断し、記録する。
    /// 切断する機器がなくても「離れている間」にする（ヘッドホンの電源を切ってから離れ、後で入れ直した場合も守るため）。
    /// スリープまでの時間が短いので、すべての機器の切断を同時に始める
    private func leave(because cause: String) async {
        stopWaitingForSilence()
        presence = .away
        let connected = connectedRegisteredDevices()
        guard !connected.isEmpty else {
            Logger.sleep.notice("離れる（\(cause, privacy: .public)）：切断する機器なし")
            return
        }
        Logger.sleep.notice("離れる（\(cause, privacy: .public)）：\(connected.map(\.rawValue).joined(separator: "、"), privacy: .public) を切断して記録する")
        // 切断より先に記録する（切断の途中でスリープに入っても、復帰したら再接続できるように）
        devicesToReconnect.formUnion(connected)

        await withTaskGroup(of: Void.self) { group in
            for address in connected {
                group.addTask { await self.deviceStore.disconnect(address) }
            }
        }
    }

    /// 「音が止まるのを待っている」にして、見張りを始める。すでに待っていれば、そのまま続ける
    /// （電源ボタンでは、ロックと画面の消灯が続けて届くため）
    private func startWaitingForSilence() {
        guard presence != .waitingForSilence else {
            return
        }
        presence = .waitingForSilence
        silenceWatcher = Task { [weak self] in
            await self?.watchForSilence()
        }
    }

    /// 見張りをやめる（戻ってきたとき、スリープなどで離れたとき）
    private func stopWaitingForSilence() {
        silenceWatcher?.cancel()
        silenceWatcher = nil
    }

    /// 一定の間隔で、登録機器から音が出ているかを読む。出ていないのが決めた回数続いたら、切断して「離れている間」にする。
    /// 途中で音が出たら（再生を再開した、次の曲が始まった）、数え直す
    private func watchForSilence() async {
        var silentChecks = 0
        while presence == .waitingForSilence {
            do {
                try await Task.sleep(for: silenceCheckInterval)
            } catch {
                return  // 取り消された（戻ってきた、スリープした）
            }
            guard presence == .waitingForSilence else {
                return
            }
            let isPlaying = connectedRegisteredDevices().contains { deviceStore.isPlaying($0) }
            silentChecks = isPlaying ? 0 : silentChecks + 1
            if silentChecks >= silentChecksBeforeLeaving {
                // 自分自身を取り消さないように、先に手放してから離れる
                silenceWatcher = nil
                await leave(because: "音が止まった")
                return
            }
        }
    }

    /// この Mac に接続中の登録機器
    private func connectedRegisteredDevices() -> [BluetoothAddress] {
        deviceStore.registeredDevices
            .map(\.address)
            .filter { deviceStore.isConnected($0) }
    }
}
