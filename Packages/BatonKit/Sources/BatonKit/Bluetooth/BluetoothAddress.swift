/// Bluetooth アドレス。
///
/// 同じ機器のアドレスでも、取得する場所によって表記が違う（docs/spikes/iobluetooth.md 4.1）。
/// - IOBluetooth：`08-f0-b6-f4-7f-fb`（小文字、ハイフン区切り）
/// - macOS のシステム情報：`08:F0:B6:F4:7F:FB`（大文字、コロン区切り）
///
/// この型は、どの表記から作っても「大文字、コロン区切り」にそろえて持つ。
/// そのため、表記が違っても同じ機器なら `==` で等しくなる。
public struct BluetoothAddress: Hashable, Sendable, CustomStringConvertible {
    /// そろえた後の表記（例：`08:F0:B6:F4:7F:FB`）
    public let rawValue: String

    /// 文字列からアドレスを作る。アドレスとして正しくない文字列なら `nil` を返す。
    ///
    /// 受け付ける表記（大文字・小文字は問わない）
    /// - `08:F0:B6:F4:7F:FB`：2桁ごとにコロンで区切る
    /// - `08-f0-b6-f4-7f-fb`：2桁ごとにハイフンで区切る
    /// - `08F0B6F47FFB`：区切りなし
    public init?(_ string: String) {
        let characters = Array(string)
        let pairs: [String]
        switch characters.count {
        case 12:
            // 区切りなし：2文字ずつに分ける
            pairs = stride(from: 0, to: 12, by: 2).map { String(characters[$0...$0 + 1]) }
        case 17:
            // 区切りあり：3文字目ごとが区切りで、すべて同じ区切り文字（":" か "-"）であること
            let separator = characters[2]
            guard separator == ":" || separator == "-" else { return nil }
            let separatorPositions = stride(from: 2, to: 17, by: 3)
            guard separatorPositions.allSatisfy({ characters[$0] == separator }) else { return nil }
            pairs = string.split(separator: separator).map(String.init)
        default:
            return nil
        }
        guard pairs.count == 6, pairs.allSatisfy({ $0.count == 2 && $0.allSatisfy(Self.isHexDigit) }) else {
            return nil
        }
        rawValue = pairs.map { $0.uppercased() }.joined(separator: ":")
    }

    public var description: String {
        rawValue
    }

    /// ASCII の 0〜9、a〜f、A〜F だけを16進数の文字として扱う
    private static func isHexDigit(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isHexDigit
    }
}

// JSON などに保存するときは、`"08:F0:B6:F4:7F:FB"` のような1つの文字列として扱う
extension BluetoothAddress: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let address = BluetoothAddress(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Bluetooth アドレスとして正しくありません：\(string)"
            )
        }
        self = address
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
