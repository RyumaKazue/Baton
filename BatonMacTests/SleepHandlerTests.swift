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
    let deviceStore: DeviceStore
    let sleepHandler: SleepHandler

    init() {
        deviceStore = DeviceStore(
            bluetooth: bluetooth,
            defaults: UserDefaults(suiteName: "SleepHandlerTests-\(UUID().uuidString)")!
        )
        sleepHandler = SleepHandler(power: power, deviceStore: deviceStore)
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
        await sleepHandler.handleUserLeaving()

        #expect(!deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect == [headphones])
    }

    @Test("登録していない機器は、接続中でも切断しない")
    func keepsUnregisteredDevices() async {
        await sleepHandler.handleUserLeaving()  // ヘッドホンは接続中だが、登録していない

        #expect(deviceStore.isConnected(headphones))
        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("未接続の登録機器は、記録しない")
    func ignoresDisconnectedRegisteredDevices() async throws {
        try register(earphones)
        await sleepHandler.handleUserLeaving()

        #expect(sleepHandler.devicesToReconnect.isEmpty)
    }

    @Test("ロックとスリープが続けて起きても（2回離れても）、記録は残り、戻ってきたら再接続する")
    func leavingTwice() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving()  // ロック
        await sleepHandler.handleUserLeaving()  // 続けてスリープ

        #expect(sleepHandler.devicesToReconnect == [headphones])
        await sleepHandler.handleUserReturned()
        #expect(deviceStore.isConnected(headphones))
    }

    // MARK: - ユーザーが戻ってきたとき

    @Test("戻ってきたら、スリープ前に接続していた機器を再接続し、記録を消す")
    func reconnectsOnReturn() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving()
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

    @Test("スリープ中にヘッドホンの側からつないできた機器は、そのまま（エラーにしない）")
    func skipsAlreadyConnectedDevices() async throws {
        try register(headphones)
        await sleepHandler.handleUserLeaving()
        bluetooth.simulateExternalConnection(headphones)  // スリープ中に、ヘッドホンの電源を入れてつながった
        await sleepHandler.handleUserReturned()

        #expect(deviceStore.isConnected(headphones))
        #expect(deviceStore.errorMessage(for: headphones) == nil)
    }

    @Test("再接続に失敗したら、あきらめる（エラーメッセージを出さず、次に戻ってきたときも再接続しない）")
    func givesUpSilentlyOnFailure() async throws {
        try register(speaker)
        bluetooth.simulateExternalConnection(speaker)  // 接続中にしてからスリープする
        await sleepHandler.handleUserLeaving()
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

        power.simulateUserLeaving()
        try await waitUntil { !deviceStore.isConnected(headphones) }

        power.simulateUserReturned()
        try await waitUntil { deviceStore.isConnected(headphones) }
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
