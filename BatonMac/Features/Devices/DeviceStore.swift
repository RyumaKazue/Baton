import BatonKit
import Foundation
import Observation

/// 登録機器と、この Mac での接続状態を持つ。
///
/// - 登録機器は UserDefaults に保存し、アプリを再起動しても残す（仕様書 13.3）
/// - 接続状態は保存しない（変わるものなので、BluetoothService から取得し、変化の通知で更新する）
/// - Bluetooth の操作は BluetoothService 越しに行うので、テストでは偽物（MockBluetoothService）に差し替えられる
@MainActor
@Observable
final class DeviceStore {
    /// Baton に登録した機器（登録した順）
    private(set) var registeredDevices: [RegisteredDevice] = []
    /// ペアリング済みの音声機器（登録画面で、登録する機器を選ぶのに使う）
    private(set) var pairedDevices: [BluetoothDeviceInfo] = []
    /// この Mac に接続している音声機器
    private(set) var connectedAddresses: Set<BluetoothAddress> = []
    /// 接続・切断の途中の機器（画面で「接続中…」などを表示し、ボタンを押せなくするのに使う）
    private(set) var operations: [BluetoothAddress: DeviceOperation] = [:]
    /// 接続・切断に失敗したときのメッセージ（機器ごと）
    private(set) var errorMessages: [BluetoothAddress: String] = [:]

    // 画面に知らせる必要のないものは、@ObservationIgnored で変化を追いかけないようにする
    @ObservationIgnored private let bluetooth: any BluetoothService
    @ObservationIgnored private let defaults: UserDefaults

    /// UserDefaults に保存するときのキー
    static let storageKey = "registeredDevices"

    /// - Parameters:
    ///   - bluetooth: 使う Bluetooth のサービス（本物か偽物）
    ///   - defaults: 保存先。テストでは、テスト専用の UserDefaults を渡す
    init(bluetooth: any BluetoothService, defaults: UserDefaults = .standard) {
        self.bluetooth = bluetooth
        self.defaults = defaults
        registeredDevices = Self.loadRegisteredDevices(from: defaults)
        refreshPairedDevices()

        // 接続・切断の変化を受け取って、接続状態を更新する
        bluetooth.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - 状態の問い合わせ

    func isRegistered(_ address: BluetoothAddress) -> Bool {
        registeredDevices.contains { $0.address == address }
    }

    func isConnected(_ address: BluetoothAddress) -> Bool {
        connectedAddresses.contains(address)
    }

    /// 接続・切断の途中なら、その操作を返す
    func operation(for address: BluetoothAddress) -> DeviceOperation? {
        operations[address]
    }

    /// 最後の接続・切断に失敗していれば、そのメッセージを返す
    func errorMessage(for address: BluetoothAddress) -> String? {
        errorMessages[address]
    }

    /// 登録しているが、今はペアリング済みの一覧に見つからない機器か（Mac とのペアリングを解除した場合など）
    func isMissingFromPairedDevices(_ address: BluetoothAddress) -> Bool {
        !pairedDevices.contains { $0.address == address }
    }

    // MARK: - 操作

    /// ペアリング済みの機器の一覧と、接続状態を取り直す
    func refreshPairedDevices() {
        pairedDevices = bluetooth.pairedAudioDevices()
        connectedAddresses = Set(pairedDevices.filter(\.isConnected).map(\.address))
    }

    /// 機器を登録する。すでに登録していれば何もしない
    func register(_ device: BluetoothDeviceInfo) {
        guard !isRegistered(device.address) else {
            return
        }
        registeredDevices.append(RegisteredDevice(address: device.address, name: device.name))
        saveRegisteredDevices()
    }

    /// 登録を解除する
    func unregister(_ address: BluetoothAddress) {
        registeredDevices.removeAll { $0.address == address }
        saveRegisteredDevices()
    }

    /// この Mac に接続する。接続が終わるまで待つ（最大で10秒ほどかかる）
    func connect(_ address: BluetoothAddress) async {
        await perform(.connecting, on: address) {
            try await bluetooth.connect(address)
            // 変化の通知でも更新されるが、通知より先に画面に反映するため、ここでも更新する
            connectedAddresses.insert(address)
        }
    }

    /// この Mac から切断する。実際に切断されるまで待つ
    func disconnect(_ address: BluetoothAddress) async {
        await perform(.disconnecting, on: address) {
            try await bluetooth.disconnect(address)
            connectedAddresses.remove(address)
        }
    }

    // MARK: - 補助

    /// 接続・切断の共通の流れ：操作中にする → 実行する → 失敗したらメッセージを残す → 操作中を解除する
    private func perform(
        _ operation: DeviceOperation,
        on address: BluetoothAddress,
        action: () async throws -> Void
    ) async {
        guard operations[address] == nil else {
            return  // 同じ機器の操作が終わっていなければ、何もしない
        }
        operations[address] = operation
        errorMessages[address] = nil
        defer { operations[address] = nil }

        do {
            try await action()
        } catch {
            errorMessages[address] = Self.message(for: error, operation: operation, deviceName: name(of: address))
        }
    }

    /// 失敗したときに表示するメッセージ（仕様書 10）
    static func message(for error: Error, operation: DeviceOperation, deviceName: String) -> String {
        if case BluetoothError.deviceNotFound = error {
            return "\(deviceName)はこの Mac とペアリングされていません"
        }
        switch operation {
        case .connecting:
            return "\(deviceName)に接続できませんでした。機器の電源と距離、ほかの端末（iPhoneなど）で使用中でないか確認してください"
        case .disconnecting:
            return "\(deviceName)の切断に失敗しました"
        }
    }

    /// 表示用の機器の名前（登録機器の名前 → ペアリング済みの機器の名前 → アドレスの順に探す）
    private func name(of address: BluetoothAddress) -> String {
        registeredDevices.first { $0.address == address }?.name
            ?? pairedDevices.first { $0.address == address }?.name
            ?? address.rawValue
    }

    private func handle(_ event: BluetoothEvent) {
        switch event {
        case .connected(let address):
            connectedAddresses.insert(address)
        case .disconnected(let address):
            connectedAddresses.remove(address)
        }
    }

    /// 登録機器を JSON にして UserDefaults に保存する
    private func saveRegisteredDevices() {
        guard let data = try? JSONEncoder().encode(registeredDevices) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// UserDefaults から登録機器を読み込む。保存がない、または読めないときは空にする
    private static func loadRegisteredDevices(from defaults: UserDefaults) -> [RegisteredDevice] {
        guard let data = defaults.data(forKey: storageKey),
              let devices = try? JSONDecoder().decode([RegisteredDevice].self, from: data) else {
            return []
        }
        return devices
    }
}

/// 機器に対して実行中の操作
enum DeviceOperation: Equatable {
    case connecting
    case disconnecting
}
