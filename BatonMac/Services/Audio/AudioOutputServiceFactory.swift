/// 本物と偽物のどちらの AudioOutputService を使うかを決める。
///
/// ダミーの Bluetooth で動いているとき（BluetoothServiceFactory.usesMock）は、出力先も偽物にする。
/// ダミーの機器に接続したときに、本物の Mac の出力先を変えないため。
/// テストのときも同じ（テストの本体は BATON_MOCK_BLUETOOTH=1 で動く）。
enum AudioOutputServiceFactory {
    @MainActor
    static func make() -> any AudioOutputService {
        BluetoothServiceFactory.usesMock ? MockAudioOutputService() : CoreAudioOutputService()
    }
}
