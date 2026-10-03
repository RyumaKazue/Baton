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

    // MARK: - 補助

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
