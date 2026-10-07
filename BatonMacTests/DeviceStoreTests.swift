import BatonKit
import Foundation
import Testing
@testable import Baton

/// DeviceStore のテスト。
/// Bluetooth は偽物（MockBluetoothService）に、保存先はテスト専用の UserDefaults に差し替える。
@MainActor
struct DeviceStoreTests {
    /// ダミーの機器のアドレス（MockBluetoothService が持っているもの）
    let headphones = BluetoothAddress("00:00:00:00:00:01")!  // 最初から接続中
    let earphones = BluetoothAddress("00:00:00:00:00:02")!   // 最初は未接続
    let speaker = BluetoothAddress("00:00:00:00:00:03")!     // 接続すると必ず失敗する

    let bluetooth = MockBluetoothService(connectionDelay: .zero, disconnectionDelay: .zero)
    /// テストごとに別の保存先を使い、本物の設定やほかのテストに影響しないようにする
    let defaults = UserDefaults(suiteName: "DeviceStoreTests-\(UUID().uuidString)")!

    private func makeStore() -> DeviceStore {
        DeviceStore(bluetooth: bluetooth, defaults: defaults)
    }

    private func pairedDevice(_ address: BluetoothAddress) throws -> BluetoothDeviceInfo {
        try #require(bluetooth.pairedAudioDevices().first { $0.address == address })
    }

    // MARK: - 登録と解除

    @Test("最初は、登録機器がない")
    func startsEmpty() {
        let store = makeStore()
        #expect(store.registeredDevices.isEmpty)
    }

    @Test("登録すると、登録機器に加わる")
    func register() throws {
        let store = makeStore()
        store.register(try pairedDevice(earphones))

        #expect(store.registeredDevices.map(\.address) == [earphones])
        #expect(store.registeredDevices.first?.name == "ダミー イヤホン")
        #expect(store.isRegistered(earphones))
    }

    @Test("同じ機器を2回登録しても、1つだけ")
    func registerTwice() throws {
        let store = makeStore()
        let device = try pairedDevice(earphones)
        store.register(device)
        store.register(device)

        #expect(store.registeredDevices.count == 1)
    }

    @Test("登録を解除すると、登録機器から消える")
    func unregister() throws {
        let store = makeStore()
        store.register(try pairedDevice(earphones))
        store.unregister(earphones)

        #expect(store.registeredDevices.isEmpty)
        #expect(!store.isRegistered(earphones))
    }

    // MARK: - 保存

    @Test("登録機器は保存され、作り直しても（再起動しても）残る")
    func persistsAcrossRestart() throws {
        let store = makeStore()
        store.register(try pairedDevice(headphones))
        store.register(try pairedDevice(earphones))

        let restarted = makeStore()
        #expect(restarted.registeredDevices.map(\.address) == [headphones, earphones])
    }

    @Test("解除も保存される")
    func unregisterPersists() throws {
        let store = makeStore()
        store.register(try pairedDevice(earphones))
        store.unregister(earphones)

        let restarted = makeStore()
        #expect(restarted.registeredDevices.isEmpty)
    }

    @Test("保存されたデータが壊れていても、空の一覧で起動する")
    func corruptedDataIsIgnored() {
        defaults.set(Data("壊れたデータ".utf8), forKey: DeviceStore.storageKey)
        let store = makeStore()
        #expect(store.registeredDevices.isEmpty)
    }

    // MARK: - 接続状態

    @Test("起動したときの接続状態を、Bluetooth から取得する")
    func initialConnectionState() {
        let store = makeStore()
        #expect(store.isConnected(headphones))
        #expect(!store.isConnected(earphones))
    }

    @Test("外で接続・切断されたら、接続状態が変わる")
    func externalChangesUpdateState() {
        let store = makeStore()

        bluetooth.simulateExternalConnection(earphones)
        #expect(store.isConnected(earphones))

        bluetooth.simulateExternalDisconnection(headphones)
        #expect(!store.isConnected(headphones))
    }

    @Test("ペアリング済みの一覧に見つからない登録機器を見分けられる")
    func missingFromPairedDevices() {
        let store = makeStore()
        let unknown = BluetoothAddress("AA:BB:CC:DD:EE:FF")!
        #expect(store.isMissingFromPairedDevices(unknown))
        #expect(!store.isMissingFromPairedDevices(earphones))
    }

    // MARK: - 接続・切断

    @Test("接続すると、接続中になる")
    func connect() async {
        let store = makeStore()
        await store.connect(earphones)

        #expect(store.isConnected(earphones))
        #expect(store.operation(for: earphones) == nil)
        #expect(store.errorMessage(for: earphones) == nil)
    }

    @Test("切断すると、未接続になる")
    func disconnect() async {
        let store = makeStore()
        await store.disconnect(headphones)

        #expect(!store.isConnected(headphones))
        #expect(store.operation(for: headphones) == nil)
    }

    @Test("接続に失敗すると、メッセージが残り、未接続のまま")
    func connectFailure() async throws {
        let store = makeStore()
        store.register(try pairedDevice(speaker))
        await store.connect(speaker)

        #expect(!store.isConnected(speaker))
        #expect(store.operation(for: speaker) == nil)
        let message = try #require(store.errorMessage(for: speaker))
        #expect(message.hasPrefix("ダミー スピーカー（接続に失敗する）に接続できませんでした"))
    }

    @Test("ペアリング済みの一覧にない機器に接続すると、ペアリングされていないというメッセージになる")
    func connectUnknownDevice() async throws {
        let store = makeStore()
        let unknown = BluetoothAddress("AA:BB:CC:DD:EE:FF")!
        await store.connect(unknown)

        let message = try #require(store.errorMessage(for: unknown))
        #expect(message == "AA:BB:CC:DD:EE:FFはこの Mac とペアリングされていません")
    }

    @Test("次の操作が成功すると、前のエラーメッセージは消える")
    func successClearsPreviousError() async {
        let store = makeStore()
        await store.connect(speaker)  // 失敗する
        #expect(store.errorMessage(for: speaker) != nil)

        await store.disconnect(speaker)  // 未接続なので、何もせずに成功する
        #expect(store.errorMessage(for: speaker) == nil)
    }

    @Test("接続・切断の途中は、操作中になる")
    func operationInProgress() async {
        // 接続に時間がかかる偽物を使い、途中の状態を確かめる
        let slowBluetooth = MockBluetoothService(connectionDelay: .milliseconds(200), disconnectionDelay: .zero)
        let store = DeviceStore(bluetooth: slowBluetooth, defaults: defaults)

        let task = Task { await store.connect(earphones) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.operation(for: earphones) == .connecting)

        await task.value
        #expect(store.operation(for: earphones) == nil)
        #expect(store.isConnected(earphones))
    }
}
