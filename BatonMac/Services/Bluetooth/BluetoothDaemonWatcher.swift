import BatonKit
import CoreBluetooth
import os

/// macOS の Bluetooth の仕組み（bluetoothd）が起動し直したことに気づいて、知らせる（#51）。
///
/// CoreBluetooth の公開の部品（CBCentralManager）の状態の変化を受け取り、
/// 起動し直すべきかの判断は BluetoothDaemonRestartDetector（BatonKit）に任せる。
/// 起動し直すかどうかを決めたら onRestartNeeded を呼ぶ（実際に起動し直すのは AppRelauncher）。
@MainActor
final class BluetoothDaemonWatcher: NSObject, CBCentralManagerDelegate {
    /// 起動し直すべきときに呼ばれる
    var onRestartNeeded: (() -> Void)?

    private var manager: CBCentralManager?
    private var detector = BluetoothDaemonRestartDetector()
    /// 起動した時刻（起動してからの時間を測るため）
    private let launchedAt = ContinuousClock.now

    /// 見張りを始める。状態の知らせは、メインスレッドで届く
    func start() {
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        // queue に .main を渡しているので、メインスレッドで呼ばれる
        MainActor.assumeIsolated {
            handle(state)
        }
    }

    private func handle(_ state: CBManagerState) {
        Logger.bluetooth.notice("Bluetooth の状態：\(Self.describe(state), privacy: .public)")
        let uptime = ContinuousClock.now - launchedAt
        let seconds = Double(uptime.components.seconds)
        guard detector.shouldRelaunch(on: Self.detectorState(state), uptime: seconds) else {
            return
        }
        onRestartNeeded?()
    }

    private static func detectorState(_ state: CBManagerState) -> BluetoothDaemonRestartDetector.State {
        switch state {
        case .resetting: .resetting
        case .poweredOn: .poweredOn
        default: .other
        }
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting（bluetoothd との接続が切れた）"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "その他（\(state.rawValue)）"
        }
    }
}
