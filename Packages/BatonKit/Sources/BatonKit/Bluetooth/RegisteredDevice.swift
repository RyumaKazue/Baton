/// Baton に登録した Bluetooth 機器。
///
/// Mac に保存するほか、iPhone に登録機器の一覧を渡すとき（devices メッセージ）にも使う。
/// 機器はアドレスで見分ける（仕様書 5.4）。
public struct RegisteredDevice: Codable, Hashable, Sendable, Identifiable {
    public let address: BluetoothAddress
    /// 登録したときの機器の名前（表示用）
    public var name: String

    public var id: BluetoothAddress {
        address
    }

    public init(address: BluetoothAddress, name: String) {
        self.address = address
        self.name = name
    }
}
