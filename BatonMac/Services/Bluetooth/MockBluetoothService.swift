import BatonKit

/// 偽物の BluetoothService（ダミーのモード）。
///
/// 本物のイヤホンがなくても、画面を作ったり動きを確かめたりできるようにする。
/// ダミーの機器を3つ持ち、接続・切断にかかる時間や、接続の失敗も再現する。
/// スキーム「BatonMac (Mock)」で起動すると、本物の代わりにこれが使われる（BluetoothServiceFactory）。
@MainActor
final class MockBluetoothService: BluetoothService {
    var onEvent: ((BluetoothEvent) -> Void)?

    /// ダミーの機器
    private struct MockDevice {
        let address: BluetoothAddress
        let name: String
        var isConnected: Bool
        /// true なら、接続しようとすると必ず失敗する（電源が切れている機器の再現）
        let failsToConnect: Bool
    }

    private var devices: [MockDevice]
    /// 操作中の機器（同じ機器に続けて操作したときの再現）
    private var busyAddresses: Set<BluetoothAddress> = []

    /// 接続にかかる時間（本物では 2〜9秒ほどかかった）
    private let connectionDelay: Duration
    /// 切断にかかる時間（本物では約1秒かかった）
    private let disconnectionDelay: Duration

    init(connectionDelay: Duration = .seconds(2), disconnectionDelay: Duration = .seconds(1)) {
        self.connectionDelay = connectionDelay
        self.disconnectionDelay = disconnectionDelay
        devices = [
            MockDevice(address: BluetoothAddress("00:00:00:00:00:01")!, name: "ダミー ヘッドホン", isConnected: true, failsToConnect: false),
            MockDevice(address: BluetoothAddress("00:00:00:00:00:02")!, name: "ダミー イヤホン", isConnected: false, failsToConnect: false),
            MockDevice(address: BluetoothAddress("00:00:00:00:00:03")!, name: "ダミー スピーカー（接続に失敗する）", isConnected: false, failsToConnect: true),
        ]
    }

    // MARK: - BluetoothService

    func pairedAudioDevices() -> [BluetoothDeviceInfo] {
        devices.map { BluetoothDeviceInfo(address: $0.address, name: $0.name, isConnected: $0.isConnected) }
    }

    func isConnected(_ address: BluetoothAddress) -> Bool {
        devices.first { $0.address == address }?.isConnected ?? false
    }

    func connect(_ address: BluetoothAddress) async throws {
        guard let index = devices.firstIndex(where: { $0.address == address }) else {
            throw BluetoothError.deviceNotFound
        }
        if devices[index].isConnected {
            return
        }
        guard busyAddresses.insert(address).inserted else {
            throw BluetoothError.operationInProgress
        }
        defer { busyAddresses.remove(address) }

        try? await Task.sleep(for: connectionDelay)
        guard !devices[index].failsToConnect else {
            throw BluetoothError.connectionFailed(code: -1)
        }
        setConnected(true, at: index)
    }

    func disconnect(_ address: BluetoothAddress) async throws {
        guard let index = devices.firstIndex(where: { $0.address == address }) else {
            throw BluetoothError.deviceNotFound
        }
        guard devices[index].isConnected else {
            return
        }
        guard busyAddresses.insert(address).inserted else {
            throw BluetoothError.operationInProgress
        }
        defer { busyAddresses.remove(address) }

        try? await Task.sleep(for: disconnectionDelay)
        setConnected(false, at: index)
    }

    // MARK: - 外での操作の再現

    /// ヘッドホンの電源を切ったときなど、Baton の外で切断されたことを再現する
    func simulateExternalDisconnection(_ address: BluetoothAddress) {
        guard let index = devices.firstIndex(where: { $0.address == address }), devices[index].isConnected else {
            return
        }
        setConnected(false, at: index)
    }

    /// ヘッドホンの電源を入れたときなど、Baton の外で接続されたことを再現する
    func simulateExternalConnection(_ address: BluetoothAddress) {
        guard let index = devices.firstIndex(where: { $0.address == address }), !devices[index].isConnected else {
            return
        }
        setConnected(true, at: index)
    }

    // MARK: - 補助

    /// 接続状態を変えて、変化を onEvent で伝える（本物の通知の代わり）
    private func setConnected(_ connected: Bool, at index: Int) {
        devices[index].isConnected = connected
        let address = devices[index].address
        onEvent?(connected ? .connected(address) : .disconnected(address))
    }
}
