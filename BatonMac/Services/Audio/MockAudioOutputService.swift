import BatonKit

/// 偽物の AudioOutputService（ダミーのモードとテストで使う）。
///
/// 本物の Mac の出力先は変えない。接続の直後に出力先がまだ現れていない場面も再現できる。
@MainActor
final class MockAudioOutputService: AudioOutputService {
    /// 今の出力先（nil は Bluetooth 以外。内蔵スピーカーやモニターなど）
    private(set) var defaultOutput: BluetoothAddress?
    /// 切り替えを頼まれた回数
    private(set) var attempts = 0

    /// 何回目に頼まれたときに、出力先の一覧に現れるか（1なら、すぐに現れる）。0なら、いつまでも現れない
    private let appearsOnAttempt: Int

    init(appearsOnAttempt: Int = 1) {
        self.appearsOnAttempt = appearsOnAttempt
    }

    func switchDefaultOutput(to address: BluetoothAddress) -> AudioOutputSwitchResult {
        attempts += 1
        guard appearsOnAttempt > 0, attempts >= appearsOnAttempt else {
            return .notFound
        }
        if defaultOutput == address {
            return .alreadyDefault
        }
        defaultOutput = address
        return .switched
    }
}
