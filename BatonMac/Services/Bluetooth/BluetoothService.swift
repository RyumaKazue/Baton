import BatonKit

/// Bluetooth の機器を操作するサービスの約束ごと（プロトコル）。
///
/// 画面や状態（DeviceStore）は、IOBluetooth を直接使わず、このプロトコル越しに Bluetooth を操作する。
/// そうすることで、本物（IOBluetoothService）と偽物（MockBluetoothService）を差し替えられる。
@MainActor
protocol BluetoothService: AnyObject {
    /// ペアリング済みの音声機器の一覧（キーボードやマウスなど、音声機器以外は含まない）
    func pairedAudioDevices() -> [BluetoothDeviceInfo]

    /// この Mac に接続しているか
    func isConnected(_ address: BluetoothAddress) -> Bool

    /// 接続する。接続が終わるまで待つ（最大で10秒ほどかかる）が、その間も画面は固まらない。
    /// 失敗したときは BluetoothError を投げる
    func connect(_ address: BluetoothAddress) async throws

    /// 切断する。実際に切断されたこと（切断の通知）を確かめるまで待つ
    func disconnect(_ address: BluetoothAddress) async throws

    /// 音声機器の接続・切断が起きたときに呼ばれる。
    /// Baton の操作だけでなく、ヘッドホンの電源のオン・オフなど、外で起きた変化も届く。
    /// 同じ変化が続けて届くことはない（重なった通知はサービスの中でまとめる）。
    var onEvent: ((BluetoothEvent) -> Void)? { get set }
}

/// ペアリング済みの機器の情報
struct BluetoothDeviceInfo: Hashable, Identifiable {
    let address: BluetoothAddress
    let name: String
    let isConnected: Bool

    var id: BluetoothAddress { address }
}

/// 接続状態の変化
enum BluetoothEvent: Equatable {
    case connected(BluetoothAddress)
    case disconnected(BluetoothAddress)
}

/// Bluetooth の操作の失敗
enum BluetoothError: Error, Equatable {
    /// ペアリング済みの機器の中に見つからない
    case deviceNotFound
    /// 接続に失敗した（電源が切れている、範囲外など）。code は IOBluetooth が返したエラーの番号
    case connectionFailed(code: Int32)
    /// 切断に失敗した
    case disconnectionFailed(code: Int32)
    /// 決められた時間内に終わらなかった
    case timedOut
    /// 同じ機器に対して、別の操作がまだ終わっていない
    case operationInProgress
}
