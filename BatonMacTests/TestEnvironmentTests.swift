import Testing
@testable import Baton

/// テストを動かす環境についてのテスト
struct TestEnvironmentTests {
    /// テストのときは、本体（Baton.app）もダミーの Bluetooth で起動する。
    /// 本物の Bluetooth に触ると、CI では使用許可のダイアログが出て、テストが始まらなくなるため
    /// （BatonMac スキームの Test の設定で、BATON_MOCK_BLUETOOTH=1 を渡している）
    @Test("テストのときは、本体もダミーの Bluetooth で動く")
    func usesMockBluetoothDuringTests() {
        #expect(BluetoothServiceFactory.usesMock)
    }
}
