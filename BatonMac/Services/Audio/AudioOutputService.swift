import BatonKit

/// Mac の音の出力先を扱うサービスの約束ごと（プロトコル）。
///
/// Baton で接続しても、接続する前の出力先がモニターなどだと、出力先がヘッドホンに切り替わらない
/// （docs/spikes/iobluetooth.md 4.2）。そこで、接続した後に出力先を切り替えるために使う。
/// 本物（CoreAudioOutputService）と偽物（MockAudioOutputService）を差し替えられる。
@MainActor
protocol AudioOutputService: AnyObject {
    /// その Bluetooth 機器を、音の出力先にする。
    /// 接続の直後で、出力先の一覧にまだ現れていなければ `.notFound` を返す（呼ぶ側が少し待ってやり直す）
    func switchDefaultOutput(to address: BluetoothAddress) -> AudioOutputSwitchResult
}

/// 出力先を切り替えた結果
enum AudioOutputSwitchResult: Equatable {
    /// 切り替えた
    case switched
    /// すでにその機器が出力先だった（何もしていない）
    case alreadyDefault
    /// 出力先の一覧に、その機器がまだない
    case notFound
    /// 切り替えに失敗した。status は CoreAudio が返したエラーの番号
    case failed(status: Int32)
}
