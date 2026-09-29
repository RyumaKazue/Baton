import Testing
@testable import BatonKit

struct BatonServiceTests {
    /// Bonjour のサービス名は「_」で始まり、15文字以内である必要がある。
    @Test func bonjourTypeIsValid() {
        let name = BatonService.bonjourType.split(separator: ".").first!
        #expect(name.hasPrefix("_"))
        #expect(name.dropFirst().count <= 15)
        #expect(BatonService.bonjourType.hasSuffix("._tcp"))
    }
}
