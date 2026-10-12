import BatonKit
import Foundation
import IOBluetooth
import os

/// IOBluetooth を使う、本物の BluetoothService。
///
/// フェーズ1の検証（docs/spikes/iobluetooth.md）で分かった注意点を反映している。
/// - 音声機器だけを扱う（一覧にはキーボードやマウスも含まれるため）
/// - 接続は、終わったら呼んでもらう方式（openConnection(_:)）にして、待っている間も画面を固まらせない
/// - 切断の完了は、isConnected() の直後の値ではなく、切断の通知で判断する
/// - 同じ通知が重なって届いても、変化は1回だけ onEvent に伝える
/// - 通知と完了の連絡は、ときどき届かなくなる（#51。原因は不明）。そのため、接続・切断の完了は
///   0.5秒ごとに isConnected() でも確かめ、resync() で接続状態を読み直して通知の登録もやり直せるようにしている
///
/// IOBluetooth は Objective-C の「ターゲットとセレクタ」の仕組みで結果を知らせてくるので、NSObject を継承している。
/// アプリが動いている間ずっと1つだけ使う前提なので、通知の登録は解除していない。
@MainActor
final class IOBluetoothService: NSObject, BluetoothService {
    var onEvent: ((BluetoothEvent) -> Void)?

    /// 接続を待つ最大の時間（検証では最大8.8秒かかった）
    private static let connectionTimeout: Duration = .seconds(20)
    /// 切断の通知を待つ最大の時間（検証では約1秒で届いた）
    private static let disconnectionTimeout: Duration = .seconds(5)
    /// 接続・切断が終わったかを isConnected() で確かめる間隔（完了の連絡が届かないときのため）
    private static let completionCheckInterval: Duration = .milliseconds(500)

    /// 接続の通知の登録の控え
    private var connectNotification: IOBluetoothUserNotification?
    /// 機器ごとの、切断の通知の登録の控え
    private var disconnectNotifications: [BluetoothAddress: IOBluetoothUserNotification] = [:]
    /// 接続中だと分かっている音声機器。通知の重なりを見分けるために使う
    private var connectedAddresses: Set<BluetoothAddress> = []
    /// 接続の完了を待っている処理（機器ごと）
    private var pendingConnections: [BluetoothAddress: PendingOperation] = [:]
    /// 切断の完了を待っている処理（機器ごと）
    private var pendingDisconnections: [BluetoothAddress: PendingOperation] = [:]

    /// 完了を待っている接続・切断の処理。
    /// 時間切れのタイマーも一緒に持ち、処理が終わったら取り消す。取り消さないと、残ったタイマーが
    /// 同じ機器の次の操作を時間切れにしてしまう（docs/spikes/sleep-reconnect.md 8.4）
    private struct PendingOperation {
        let continuation: CheckedContinuation<Void, Error>
        var timeout: Task<Void, Never>?
    }

    override init() {
        super.init()
        registerConnectNotification()
    }

    /// 接続の通知を登録する（登録し直すときは、前の登録を解除してから）。
    /// 登録した時点ですでに接続中の機器についても、すぐに通知が届く（検証 4.5）
    private func registerConnectNotification() {
        connectNotification?.unregister()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:fromDevice:))
        )
    }

    // MARK: - BluetoothService

    func pairedAudioDevices() -> [BluetoothDeviceInfo] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices
            .compactMap { device -> BluetoothDeviceInfo? in
                guard Self.isAudioDevice(device), let address = Self.address(of: device) else {
                    return nil
                }
                return BluetoothDeviceInfo(
                    address: address,
                    name: device.name ?? address.rawValue,
                    isConnected: device.isConnected()
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isConnected(_ address: BluetoothAddress) -> Bool {
        device(for: address)?.isConnected() ?? false
    }

    func connect(_ address: BluetoothAddress) async throws {
        guard let device = device(for: address) else {
            throw BluetoothError.deviceNotFound
        }
        if device.isConnected() {
            return
        }
        guard pendingConnections[address] == nil else {
            throw BluetoothError.operationInProgress
        }
        Logger.bluetooth.notice("接続を開始：\(address, privacy: .public)")

        // 「終わったら呼んでもらう」方式の API を、async で待てる形に包む
        try await withCheckedThrowingContinuation { continuation in
            pendingConnections[address] = PendingOperation(continuation: continuation)

            // ターゲット（self）を渡すと、すぐに処理が戻り、接続が終わったときに connectionComplete(_:status:) が呼ばれる
            let result = device.openConnection(self)
            guard result == kIOReturnSuccess else {
                finishConnection(address, with: .failure(BluetoothError.connectionFailed(code: result)))
                return
            }
            // すでに終わっていれば、タイマーは要らない
            guard pendingConnections[address] != nil else {
                return
            }

            // 完了の連絡が届かないことがあるので（#51）、0.5秒ごとに、つながったかを直接確かめる。
            // 決めた時間までにつながらなければ、時間切れにする。完了したら finishConnection で取り消す
            pendingConnections[address]?.timeout = Task { [weak self] in
                let deadline = ContinuousClock.now + Self.connectionTimeout
                while ContinuousClock.now < deadline {
                    do {
                        try await Task.sleep(for: Self.completionCheckInterval)
                    } catch {
                        return  // 取り消された（完了の連絡が来た）
                    }
                    guard let self else { return }
                    if let device = self.device(for: address), device.isConnected() {
                        self.noteConnected(device, address: address, source: "つながったことを確認")
                        self.finishConnection(address, with: .success(()))
                        return
                    }
                }
                self?.finishConnection(address, with: .failure(BluetoothError.timedOut))
            }
        }
    }

    func disconnect(_ address: BluetoothAddress) async throws {
        guard let device = device(for: address) else {
            throw BluetoothError.deviceNotFound
        }
        guard device.isConnected() else {
            return
        }
        guard pendingDisconnections[address] == nil else {
            throw BluetoothError.operationInProgress
        }
        Logger.bluetooth.notice("切断を開始：\(address, privacy: .public)")

        try await withCheckedThrowingContinuation { continuation in
            pendingDisconnections[address] = PendingOperation(continuation: continuation)

            // closeConnection() はすぐに「成功」を返すが、実際の切断は少し後（検証 4.2）。
            // 完了は deviceDisconnected(_:fromDevice:) で受け取る
            let result = device.closeConnection()
            guard result == kIOReturnSuccess else {
                finishDisconnection(address, with: .failure(BluetoothError.disconnectionFailed(code: result)))
                return
            }
            // すでに終わっていれば、タイマーは要らない
            guard pendingDisconnections[address] != nil else {
                return
            }

            // 切断の通知が届かないことがあるので（#51）、0.5秒ごとに、切れたかを直接確かめる。
            // 決めた時間までに切れなければ、時間切れにする。通知が来たら finishDisconnection で取り消す
            pendingDisconnections[address]?.timeout = Task { [weak self] in
                let deadline = ContinuousClock.now + Self.disconnectionTimeout
                while ContinuousClock.now < deadline {
                    do {
                        try await Task.sleep(for: Self.completionCheckInterval)
                    } catch {
                        return  // 取り消された（切断の通知が来た）
                    }
                    guard let self else { return }
                    if self.device(for: address)?.isConnected() != true {
                        self.disconnectNotifications.removeValue(forKey: address)?.unregister()
                        self.noteDisconnected(address, name: nil, source: "切れたことを確認")
                        self.finishDisconnection(address, with: .success(()))
                        return
                    }
                }
                self?.finishDisconnection(address, with: .failure(BluetoothError.timedOut))
            }
        }
    }

    // MARK: - IOBluetooth からの呼び出し

    /// 機器が接続したとき（Baton の操作でも、外での操作でも呼ばれる）
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        guard Self.isAudioDevice(device), let address = Self.address(of: device) else {
            return
        }
        noteConnected(device, address: address, source: "接続の通知")
    }

    /// 機器が切断したとき
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        guard let address = Self.address(of: device) else {
            return
        }
        notification.unregister()
        disconnectNotifications[address] = nil
        finishDisconnection(address, with: .success(()))
        noteDisconnected(address, name: device.name, source: "切断の通知")
    }

    // MARK: - 読み直し

    func resync() {
        // 通知の登録をやり直す。登録し直すと、すでにつながっている機器の接続の通知も、少し後に届く
        registerConnectNotification()

        // 届いていなかった変化を、直接聞いて合わせる
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter(Self.isAudioDevice)
        var actuallyConnected: [BluetoothAddress: IOBluetoothDevice] = [:]
        for device in devices where device.isConnected() {
            if let address = Self.address(of: device) {
                actuallyConnected[address] = device
            }
        }
        let missedConnections = Set(actuallyConnected.keys).subtracting(connectedAddresses)
        let missedDisconnections = connectedAddresses.subtracting(actuallyConnected.keys)
        guard !missedConnections.isEmpty || !missedDisconnections.isEmpty else {
            Logger.bluetooth.debug("読み直し：ずれはなかった")
            return
        }
        Logger.bluetooth.notice("読み直し：届いていなかった変化があった（つながっていた：\(missedConnections.map(\.rawValue).joined(separator: "、"), privacy: .public)、切れていた：\(missedDisconnections.map(\.rawValue).joined(separator: "、"), privacy: .public)）")
        for address in missedDisconnections {
            disconnectNotifications.removeValue(forKey: address)?.unregister()
            noteDisconnected(address, name: nil, source: "読み直しで切れていた")
        }
        for (address, device) in actuallyConnected where missedConnections.contains(address) {
            noteConnected(device, address: address, source: "読み直しでつながっていた")
        }
    }

    // MARK: - 接続状態の記録

    /// つながったことを記録し、新しい変化なら onEvent で伝える。
    /// 切断の通知は機器ごとに登録する。二重に登録しないよう、前の登録は解除してから登録し直す
    private func noteConnected(_ device: IOBluetoothDevice, address: BluetoothAddress, source: String) {
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:fromDevice:))
        )

        // すでに接続中だと分かっている機器なら、重なって届いた通知なので伝えない
        guard connectedAddresses.insert(address).inserted else {
            Logger.bluetooth.debug("\(source, privacy: .public)（重なりのため無視）：\(address, privacy: .public)")
            return
        }
        Logger.bluetooth.notice("\(source, privacy: .public)：\(device.name ?? "?", privacy: .public)（\(address, privacy: .public)）")
        onEvent?(.connected(address))
    }

    /// 切れたことを記録し、新しい変化なら onEvent で伝える
    private func noteDisconnected(_ address: BluetoothAddress, name: String?, source: String) {
        guard connectedAddresses.remove(address) != nil else {
            Logger.bluetooth.debug("\(source, privacy: .public)（重なりのため無視）：\(address, privacy: .public)")
            return
        }
        Logger.bluetooth.notice("\(source, privacy: .public)：\(name ?? "?", privacy: .public)（\(address, privacy: .public)）")
        onEvent?(.disconnected(address))
    }

    /// openConnection(_:) の接続が終わったとき
    @objc private func connectionComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        guard let device, let address = Self.address(of: device) else {
            return
        }
        let result: Result<Void, Error> = status == kIOReturnSuccess
            ? .success(())
            : .failure(BluetoothError.connectionFailed(code: status))
        finishConnection(address, with: result)
    }

    // MARK: - 補助

    /// 待っている接続の処理を終わらせる。すでに終わっていれば何もしない（完了と時間切れの、先に来た方だけが効く）
    private func finishConnection(_ address: BluetoothAddress, with result: Result<Void, Error>) {
        guard let pending = pendingConnections.removeValue(forKey: address) else {
            return
        }
        pending.timeout?.cancel()
        Self.log("接続", address: address, result: result)
        pending.continuation.resume(with: result)
    }

    /// 待っている切断の処理を終わらせる。すでに終わっていれば何もしない（通知と時間切れの、先に来た方だけが効く）
    private func finishDisconnection(_ address: BluetoothAddress, with result: Result<Void, Error>) {
        guard let pending = pendingDisconnections.removeValue(forKey: address) else {
            return
        }
        pending.timeout?.cancel()
        Self.log("切断", address: address, result: result)
        pending.continuation.resume(with: result)
    }

    /// 接続・切断の結果をログに出す
    private static func log(_ operation: String, address: BluetoothAddress, result: Result<Void, Error>) {
        switch result {
        case .success:
            Logger.bluetooth.notice("\(operation, privacy: .public)に成功：\(address, privacy: .public)")
        case .failure(let error):
            Logger.bluetooth.error("\(operation, privacy: .public)に失敗：\(address, privacy: .public)、\(String(describing: error), privacy: .public)")
        }
    }

    private func device(for address: BluetoothAddress) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: address.rawValue)
    }

    private static func address(of device: IOBluetoothDevice) -> BluetoothAddress? {
        device.addressString.flatMap { BluetoothAddress($0) }
    }

    private static func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
    }
}
