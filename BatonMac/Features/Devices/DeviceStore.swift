import BatonKit
import Foundation
import Observation
import os

/// 登録機器と、この Mac での接続状態を持つ。
///
/// - 登録機器は UserDefaults に保存し、アプリを再起動しても残す（仕様書 13.3）
/// - 接続状態は保存しない（変わるものなので、BluetoothService から取得し、変化の通知で更新する）
/// - Bluetooth の操作は BluetoothService 越しに行うので、テストでは偽物（MockBluetoothService）に差し替えられる
/// - Baton が接続したら、音の出力先をその機器に切り替える（AudioOutputService 越し。偽物に差し替えられる）
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
    @ObservationIgnored private let audioOutput: any AudioOutputService
    @ObservationIgnored private let defaults: UserDefaults
    /// 出力先の一覧に現れるのを待つ間隔
    @ObservationIgnored private let audioOutputRetryInterval: Duration

    /// 出力先の一覧に現れるのを待つ回数（間隔0.5秒なら、最大で約5秒待つ）
    static let maxAudioOutputAttempts = 10

    /// 機器がこの Mac につながったときに呼ばれる（Baton の操作でも、外で起きた接続でも）。
    /// DeviceStore は、誰が受け取って何をするかを知らない。今は SleepHandler が受け取り、
    /// 離れている間なら切断する（DeviceStore から SleepHandler への依存を作らないため、処理を渡してもらう形にしている）
    /// メインスレッドで呼ぶので、受け取る側はその場で自分の状態を見て判断できる
    @ObservationIgnored var onDeviceConnected: (@MainActor (BluetoothAddress) -> Void)?

    /// UserDefaults に保存するときのキー
    static let storageKey = "registeredDevices"

    /// - Parameters:
    ///   - bluetooth: 使う Bluetooth のサービス（本物か偽物）
    ///   - audioOutput: 使う出力先のサービス（本物か偽物）
    ///   - defaults: 保存先。テストでは、テスト専用の UserDefaults を渡す
    ///   - audioOutputRetryInterval: 出力先の一覧に現れるのを待つ間隔。テストでは 0 にする
    init(
        bluetooth: any BluetoothService,
        audioOutput: any AudioOutputService,
        defaults: UserDefaults = .standard,
        audioOutputRetryInterval: Duration = .milliseconds(500)
    ) {
        self.bluetooth = bluetooth
        self.audioOutput = audioOutput
        self.defaults = defaults
        self.audioOutputRetryInterval = audioOutputRetryInterval
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
        Logger.devices.notice("登録：\(device.name, privacy: .public)（\(device.address, privacy: .public)）")
    }

    /// 登録を解除する
    func unregister(_ address: BluetoothAddress) {
        registeredDevices.removeAll { $0.address == address }
        saveRegisteredDevices()
        Logger.devices.notice("登録を解除：\(address, privacy: .public)")
    }

    /// この Mac に接続する。接続が終わるまで待つ（最大で10秒ほどかかる）。
    /// 接続できたら、音の出力先をその機器に切り替える
    /// - Parameter reportsErrors: false なら、失敗してもエラーメッセージを残さない（復帰時の自動の再接続など）
    func connect(_ address: BluetoothAddress, reportsErrors: Bool = true) async {
        let connected = await perform(.connecting, on: address, reportsErrors: reportsErrors) {
            try await bluetooth.connect(address)
            // 変化の通知でも更新されるが、通知より先に画面に反映するため、ここでも更新する
            connectedAddresses.insert(address)
        }
        if connected {
            await switchAudioOutput(to: address)
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
    /// - Returns: 実行して成功したら true（失敗したとき、同じ機器の操作が終わっていなくて何もしなかったときは false）
    @discardableResult
    private func perform(
        _ operation: DeviceOperation,
        on address: BluetoothAddress,
        reportsErrors: Bool = true,
        action: () async throws -> Void
    ) async -> Bool {
        guard operations[address] == nil else {
            return false  // 同じ機器の操作が終わっていなければ、何もしない
        }
        operations[address] = operation
        errorMessages[address] = nil
        defer { operations[address] = nil }

        do {
            try await action()
            return true
        } catch {
            Logger.devices.error("\(operation == .connecting ? "接続" : "切断", privacy: .public)できなかった：\(self.name(of: address), privacy: .public)、\(String(describing: error), privacy: .public)\(reportsErrors ? "" : "（メッセージは出さない）", privacy: .public)")
            if reportsErrors {
                errorMessages[address] = Self.message(for: error, operation: operation, deviceName: name(of: address))
            }
            return false
        }
    }

    /// 音の出力先を、接続した機器に切り替える。接続する前の出力先がモニターなどだと、
    /// 接続しても出力先が切り替わらないため（docs/spikes/iobluetooth.md 4.2）。
    /// 接続の直後は、出力先の一覧にまだ現れていないことがあるので、少しずつ待ってやり直す。
    /// 切り替えられなくても、接続はできているので、エラーメッセージは出さずにログだけ残す
    private func switchAudioOutput(to address: BluetoothAddress) async {
        let start = ContinuousClock.now
        for attempt in 1...Self.maxAudioOutputAttempts {
            let result = audioOutput.switchDefaultOutput(to: address)
            let elapsed = ContinuousClock.now - start
            switch result {
            case .switched:
                Logger.devices.notice("出力先を切り替えた：\(self.name(of: address), privacy: .public)（\(attempt, privacy: .public)回目、\(elapsed, privacy: .public)）")
                return
            case .alreadyDefault:
                Logger.devices.notice("出力先はすでに \(self.name(of: address), privacy: .public)（\(attempt, privacy: .public)回目、\(elapsed, privacy: .public)）")
                return
            case .failed(let status):
                Logger.devices.error("出力先を切り替えられなかった：\(self.name(of: address), privacy: .public)、status=\(status, privacy: .public)")
                return
            case .notFound:
                guard attempt < Self.maxAudioOutputAttempts else {
                    Logger.devices.error("出力先の一覧に現れなかったので、切り替えない：\(self.name(of: address), privacy: .public)（\(elapsed, privacy: .public)）")
                    return
                }
                try? await Task.sleep(for: audioOutputRetryInterval)
            }
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
            onDeviceConnected?(address)
        case .disconnected(let address):
            connectedAddresses.remove(address)
        }
    }

    /// 登録機器を JSON にして UserDefaults に保存する
    private func saveRegisteredDevices() {
        guard let data = try? JSONEncoder().encode(registeredDevices) else {
            Logger.devices.error("登録機器を保存できなかった")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// UserDefaults から登録機器を読み込む。保存がない、または読めないときは空にする
    private static func loadRegisteredDevices(from defaults: UserDefaults) -> [RegisteredDevice] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        guard let devices = try? JSONDecoder().decode([RegisteredDevice].self, from: data) else {
            Logger.devices.error("保存されていた登録機器を読み込めなかった（空の一覧で起動する）")
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
