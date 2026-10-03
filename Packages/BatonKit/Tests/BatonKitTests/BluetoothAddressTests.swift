import Foundation
import Testing
@testable import BatonKit

struct BluetoothAddressTests {
    // MARK: - 表記をそろえる

    @Test("IOBluetooth の表記（小文字、ハイフン）を、大文字・コロン区切りにそろえる")
    func normalizesIOBluetoothFormat() {
        let address = BluetoothAddress("08-f0-b6-f4-7f-fb")
        #expect(address?.rawValue == "08:F0:B6:F4:7F:FB")
    }

    @Test("システム情報の表記（大文字、コロン）は、そのまま")
    func keepsSystemInformationFormat() {
        let address = BluetoothAddress("08:F0:B6:F4:7F:FB")
        #expect(address?.rawValue == "08:F0:B6:F4:7F:FB")
    }

    @Test("区切りのない表記も受け付ける")
    func acceptsNoSeparators() {
        let address = BluetoothAddress("08f0b6f47ffb")
        #expect(address?.rawValue == "08:F0:B6:F4:7F:FB")
    }

    @Test("表記が違っても、同じ機器なら等しい")
    func equalAcrossFormats() {
        #expect(BluetoothAddress("08-f0-b6-f4-7f-fb") == BluetoothAddress("08:F0:B6:F4:7F:FB"))
    }

    // MARK: - 正しくない文字列

    @Test("正しくない文字列からは作れない", arguments: [
        "",                       // 空
        "08:F0:B6:F4:7F",         // 桁が足りない
        "08:F0:B6:F4:7F:FB:00",   // 桁が多い
        "08:F0:B6:F4:7F:FG",      // 16進数でない文字（G）
        "08 F0 B6 F4 7F FB",      // 許可していない区切り（スペース）
        "08:F0:B6:F4:7F:FB-tacl", // 余計な文字が付いている
        "０８:F0:B6:F4:7F:FB",    // 全角の数字
        "0-8F0B6F47FFB",          // 区切りの位置がおかしい
        "08:F0-B6:F4:7F:FB",      // 区切り文字が混ざっている
        "08::F0:B6:F4:7F:F",      // 区切りが続いている
    ])
    func rejectsInvalidStrings(_ string: String) {
        #expect(BluetoothAddress(string) == nil)
    }

    // MARK: - 保存（Codable）

    @Test("1つの文字列として JSON に保存し、元に戻せる")
    func codableRoundTrip() throws {
        let address = try #require(BluetoothAddress("08-f0-b6-f4-7f-fb"))
        let data = try JSONEncoder().encode(address)
        #expect(String(data: data, encoding: .utf8) == #""08:F0:B6:F4:7F:FB""#)
        #expect(try JSONDecoder().decode(BluetoothAddress.self, from: data) == address)
    }

    @Test("正しくないアドレスの JSON は読み込めない")
    func decodingInvalidAddressFails() {
        let data = Data(#""not-an-address""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BluetoothAddress.self, from: data)
        }
    }
}

struct RegisteredDeviceTests {
    @Test("登録機器を JSON に保存し、元に戻せる")
    func codableRoundTrip() throws {
        let device = RegisteredDevice(
            address: try #require(BluetoothAddress("08:F0:B6:F4:7F:FB")),
            name: "EDIFIER W820NB Plus"
        )
        let data = try JSONEncoder().encode(device)
        #expect(try JSONDecoder().decode(RegisteredDevice.self, from: data) == device)
    }
}
