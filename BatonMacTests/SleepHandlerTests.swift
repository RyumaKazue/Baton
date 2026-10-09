import BatonKit
import Foundation
import Testing
@testable import Baton

/// SleepHandler のテスト。
/// 離れた・戻ってきたの通知は偽物（MockPowerEventService）に、Bluetooth は偽物（MockBluetoothService）に差し替える。
@MainActor
struct SleepHandlerTests {
    let headphones = BluetoothAddress("00:00:00:00:00:01")!  // 最初から接続中
    let earphones = BluetoothAddress("00:00:00:00:00:02")!   // 最初は未接続
    let speaker = BluetoothAddress("00:00:00:00:00:03")!     // 接続すると必ず失敗する

    let bluetooth = MockBluetoothService(connectionDelay: .zero, disconnectionDelay: .zero)
    let power = MockPowerEventService()
    let audioOutput = MockAudioOutputService()
    let deviceStore: DeviceStore
    let settings: AppSettings
    let sleepHandler: SleepHandler

    init() {
        let defaults = UserDefaults(suiteName: "SleepHandlerTests-\(UUID().uuidString)")!
        deviceStore = DeviceStore(
            bluetooth: bluetooth,
            audioOutput: audioOutput,
            defaults: defaults,
            audioOutputRetryInterval: .zero
        )
        settings = AppSettings(defaults: defaults)  // 初期値：ロック・スリープはオン、画面の消灯はオフ、再生中は切断しない
        // 音が出ていないのが3回続いたら切断する（本物は2秒ごとに15回。テストでは待たずに済むようにする）
        sleepHandler = SleepHandler(
            power: power,
            deviceStore: deviceStore,
            settings: settings,
            silenceCheckInterval: .zero,
            silentChecksBeforeLeaving: 3
        )
    }

    private func register(_ addresses: BluetoothAddress...) throws {
        for address in addresses {
            let device = try #require(bluetooth.pairedAudioDevices().first { $0.address == address })
            deviceStore.register(device)
        }
    }

    // MARK: - 離れるとき（スリープ・ロック）

    @Test("離れるとき、接続中の登録機器を切断して記録する")
    func disconnectsConnectedRegisteredDevices() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect == [headphones])
    }

    @Test("登録していない機器は、接続中でも切断しない")
    func keepsUnregisteredDevices() async {
        await sleepHandler.handleUserLeaving(reason: .sleep)  // ヘッドホンは接続中だが、登録していない

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("未接続の登録機器は、記録しない")
    func ignoresDisconnectedRegisteredDevices() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)

        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("ロックとスリープが続けて起きても（2回離れても）、記録は残り、戻ってきたら再接続する")
    func leavingTwice() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving(reason: .screenLock)
        await sleepHandler.handleUserLeaving(reason: .sleep)  // 続けてスリープ

        #expect(sleepHandler.devicesToReconnect == [headphones])
        await sleepHandler.handleUserReturned()
        #expect(deviceStore.isConnected(headphones))
    }

    // MARK: - 切断のきっかけの設定

    @Test("初期値では、画面が消えただけでは切断しない")
    func keepsConnectionOnDisplaySleepByDefault() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving(reason: .displaySleep)

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("設定をオンにすると、画面が消えたときに切断する")
    func disconnectsOnDisplaySleepWhenEnabled() async throws {
        try register(headphones)
        settings.disconnectsOnDisplaySleep = true
        await sleepHandler.handleUserLeaving(reason: .displaySleep)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect == [headphones])
    }

    @Test("ロックの設定がオフなら、ロックでは切断せず、続けてスリープしたときに切断する")
    func disconnectsOnlyOnSleepWhenLockIsOff() async throws {
        try register(headphones)
        settings.disconnectsOnScreenLock = false

        await sleepHandler.handleUserLeaving(reason: .screenLock)
        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect.isEmpty)

        await sleepHandler.handleUserLeaving(reason: .sleep)
        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect == [headphones])
    }

    @Test("設定がオフで切断しなかったときは、戻ってきても何もしない（記録がないため）")
    func doesNothingOnReturnWhenNotDisconnected() async throws {
        try register(headphones)
        settings.disconnectsOnSleep = false
        await sleepHandler.handleUserLeaving(reason: .sleep)
        bluetooth.simulateExternalDisconnection(headphones)  // スリープ中に、ヘッドホンの電源を切った
        await sleepHandler.handleUserReturned()

        #expect(!deviceStore.isConnected(headphones))
    }

    // MARK: - 離れている間につないできたとき

    @Test("離れるときに切断する機器がなくても、離れている間になる")
    func becomesAwayWithoutConnectedDevices() async throws {
        try register(earphones)  // 未接続
        await sleepHandler.handleUserLeaving(reason: .sleep)

        #expect(sleepHandler.isAway)
    }

    @Test("離れている間に登録機器がつないできたら切断し、戻ってきたら再接続する")
    func disconnectsDevicesConnectingWhileAway() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)

        bluetooth.simulateExternalConnection(earphones)  // スリープ中に、ヘッドホンの電源を入れた
        try await waitUntil { !deviceStore.isConnected(earphones) }
        #expect(sleepHandler.devicesToReconnect == [earphones])

        await sleepHandler.handleUserReturned()
        #expect(deviceStore.isConnected(earphones))
        #expect(!sleepHandler.isAway)
    }

    @Test("離れていないときにつないできた機器は、切断しない")
    func keepsDevicesConnectingWhileNotAway() async throws {
        try register(earphones)

        bluetooth.simulateExternalConnection(earphones)
        try await settle()
        #expect(deviceStore.isConnected(earphones))
    }

    @Test("離れている間でも、登録していない機器は切断しない")
    func keepsUnregisteredDevicesConnectingWhileAway() async throws {
        await sleepHandler.handleUserLeaving(reason: .sleep)

        bluetooth.simulateExternalConnection(earphones)  // 登録していない
        try await settle()
        #expect(deviceStore.isConnected(earphones))
    }

    @Test("設定がオフのきっかけで離れたときは、離れている間にならず、つないできた機器を切断しない")
    func keepsDevicesWhenLeaveSettingIsOff() async throws {
        try register(earphones)
        settings.disconnectsOnScreenLock = false
        await sleepHandler.handleUserLeaving(reason: .screenLock)
        #expect(!sleepHandler.isAway)

        bluetooth.simulateExternalConnection(earphones)
        try await settle()
        #expect(deviceStore.isConnected(earphones))
    }

    @Test("戻ってきた後につないできた機器は、切断しない")
    func keepsDevicesConnectingAfterReturn() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)
        await sleepHandler.handleUserReturned()

        bluetooth.simulateExternalConnection(earphones)
        try await settle()
        #expect(deviceStore.isConnected(earphones))
    }

    @Test("何度もつないでくる機器は、3回切断したら切るのをやめ、戻ってきたときは接続済みなので何もしない")
    func stopsDisconnectingAfterRepeatedConnections() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)

        for _ in 1...3 {
            bluetooth.simulateExternalConnection(earphones)
            try await waitUntil { !deviceStore.isConnected(earphones) }
        }
        bluetooth.simulateExternalConnection(earphones)  // 4回目
        try await settle()
        #expect(deviceStore.isConnected(earphones))

        await sleepHandler.handleUserReturned()  // すでに接続済みなので、接続し直さない
        #expect(deviceStore.isConnected(earphones))
        #expect(deviceStore.errorMessage(for: earphones) == nil)
    }

    @Test("安全弁の回数は、戻ってきたら0に戻る")
    func resetsLimiterOnReturn() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)
        for _ in 1...3 {
            bluetooth.simulateExternalConnection(earphones)
            try await waitUntil { !deviceStore.isConnected(earphones) }
        }
        await sleepHandler.handleUserReturned()  // 再接続される

        await sleepHandler.handleUserLeaving(reason: .sleep)  // また離れる（ここで切断される）
        bluetooth.simulateExternalConnection(earphones)
        try await waitUntil { !deviceStore.isConnected(earphones) }
    }

    // MARK: - 再生中は切断しない

    @Test("再生中にロックしたら切断せず、音が止まるのを待つ")
    func keepsConnectionWhenLockedWhilePlaying() async throws {
        try register(headphones)
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .screenLock)
        try await settle()

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.presence == .waitingForSilence)
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("再生していないときにロックしたら、今までどおり切断する")
    func disconnectsWhenLockedWithoutPlaying() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving(reason: .screenLock)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.isAway)
    }

    @Test("再生中に画面が消えても（設定がオンのとき）、切断しない")
    func keepsConnectionOnDisplaySleepWhilePlaying() async throws {
        try register(headphones)
        settings.disconnectsOnDisplaySleep = true
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .displaySleep)

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.presence == .waitingForSilence)
    }

    @Test("再生中でも、スリープでは切断する")
    func disconnectsOnSleepWhilePlaying() async throws {
        try register(headphones)
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .sleep)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.isAway)
    }

    @Test("待っている間に音が止まったら、決めた回数の後に切断し、戻ってきたら再接続する")
    func disconnectsAfterAudioStops() async throws {
        try register(headphones)
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .screenLock)

        audioOutput.playingDevices = []  // 一時停止した
        try await waitUntil { sleepHandler.isAway }
        try await waitUntil { !deviceStore.isConnected(headphones) }
        #expect(sleepHandler.devicesToReconnect == [headphones])

        await sleepHandler.handleUserReturned()
        #expect(deviceStore.isConnected(headphones))
    }

    @Test("待っている間に再生を再開したら、数え直す")
    func restartsCountingWhenPlaybackResumes() async throws {
        try register(headphones)
        // ロックのときは再生中 → 止まる、止まる → 再開 → 止まる、止まる、止まる（ここで3回続く）
        audioOutput.scriptedPlaying = [true, false, false, true, false, false, false]
        await sleepHandler.handleUserLeaving(reason: .screenLock)

        try await waitUntil { sleepHandler.isAway }
        #expect(audioOutput.isPlayingCalls == 7)  // 再開がなければ、4回目で切断していた
    }

    @Test("待っている間にロックを解除したら、何もしない（切断も再接続もしない）")
    func returnsWhileWaitingForSilence() async throws {
        try register(headphones)
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .screenLock)
        await sleepHandler.handleUserReturned()

        audioOutput.playingDevices = []  // 戻った後に止めても、見張りは終わっているので切断しない
        try await settle()
        #expect(sleepHandler.presence == .present)
        #expect(deviceStore.isConnected(headphones))
    }

    @Test("待っている間にスリープしたら、切断する")
    func disconnectsOnSleepWhileWaitingForSilence() async throws {
        try register(headphones)
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .screenLock)
        await sleepHandler.handleUserLeaving(reason: .sleep)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.isAway)
    }

    @Test("「再生中は切断しない」がオフなら、再生中でもロックで切断する")
    func disconnectsWhilePlayingWhenSettingIsOff() async throws {
        try register(headphones)
        settings.keepsConnectionWhilePlaying = false
        audioOutput.playingDevices = [headphones]
        await sleepHandler.handleUserLeaving(reason: .screenLock)

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.isAway)
    }

    // MARK: - ユーザーが戻ってきたとき

    @Test("戻ってきたら、スリープ前に接続していた機器を再接続し、記録を消す")
    func reconnectsOnReturn() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving(reason: .sleep)
        await sleepHandler.handleUserReturned()

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("離れていないのに戻ってきた（画面だけが点いたなど）ときは、何もしない")
    func doesNothingWithoutSleep() async throws {
        try register(earphones)
        await sleepHandler.handleUserReturned()

        #expect(!deviceStore.isConnected(earphones))
    }

    @Test("再接続に失敗したら、あきらめる（エラーメッセージを出さず、次に戻ってきたときも再接続しない）")
    func givesUpSilentlyOnFailure() async throws {
        try register(speaker)
        bluetooth.simulateExternalConnection(speaker)  // 接続中にしてからスリープする
        await sleepHandler.handleUserLeaving(reason: .sleep)
        #expect(sleepHandler.devicesToReconnect == [speaker])

        await sleepHandler.handleUserReturned()  // 再接続は失敗する
        #expect(!deviceStore.isConnected(speaker))
        #expect(deviceStore.errorMessage(for: speaker) == nil)
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    // MARK: - 通知とのつながり

    @Test("離れた・戻ってきたの通知が来ると、切断と再接続が行われる")
    func respondsToPowerEvents() async throws {
        try register(headphones)

        power.simulateUserLeaving(.sleep)
        try await waitUntil { !deviceStore.isConnected(headphones) }

        power.simulateUserReturned()
        try await waitUntil { deviceStore.isConnected(headphones) }
    }

    /// 通知から先の処理（Task の中で動く）が終わるのを、少し待つ。
    /// 「切断されない」ことは条件で待てないので、処理が動き終わるだけの時間を待ってから確かめる
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    /// 条件が満たされるまで、少しずつ待つ（通知から先の処理は Task の中で動くため）
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(1)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            #expect(ContinuousClock.now < deadline, "時間内に条件を満たさなかった")
            guard ContinuousClock.now < deadline else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
