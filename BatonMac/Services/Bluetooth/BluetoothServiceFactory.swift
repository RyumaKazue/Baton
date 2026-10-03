import Foundation

/// 本物と偽物のどちらの BluetoothService を使うかを決める。
///
/// 環境変数 `BATON_MOCK_BLUETOOTH` が `1` なら偽物（ダミーのモード）を使う。
/// この環境変数は、スキーム「BatonMac (Mock)」の Run の設定で渡している。
/// 環境変数は Xcode から起動したときだけ渡るので、Finder などから起動すると、必ず本物が使われる。
enum BluetoothServiceFactory {
    static let mockEnvironmentKey = "BATON_MOCK_BLUETOOTH"

    /// ダミーのモードで動いているか
    static var usesMock: Bool {
        ProcessInfo.processInfo.environment[mockEnvironmentKey] == "1"
    }

    @MainActor
    static func make() -> any BluetoothService {
        usesMock ? MockBluetoothService() : IOBluetoothService()
    }
}
