import Foundation
import Testing
@testable import BatonKit

/// 安全弁のテスト。`#expect` の中では値を書き換える関数を呼べないので、結果をいったん変数に入れて確かめる
struct RepeatedConnectionLimiterTests {
    let headphones = BluetoothAddress("00:00:00:00:00:01")!
    let earphones = BluetoothAddress("00:00:00:00:00:02")!
    let start = Date(timeIntervalSince1970: 0)

    @Test("5分以内なら3回までは切ってよく、4回目は切らない")
    func stopsAfterThreeInWindow() {
        var limiter = RepeatedConnectionLimiter()
        let answers = [0, 5, 10, 15].map { limiter.allowsDisconnect(headphones, at: start + TimeInterval($0)) }

        #expect(answers == [true, true, true, false])
    }

    @Test("5分より前に切った回は数えない")
    func forgetsOldDisconnections() {
        var limiter = RepeatedConnectionLimiter()
        for offset in [0, 10, 20] {
            _ = limiter.allowsDisconnect(headphones, at: start + TimeInterval(offset))
        }

        // 最初の回から5分が過ぎたので、数えるのは2回（10秒と20秒の回）
        let allowed = limiter.allowsDisconnect(headphones, at: start + 5 * 60)
        #expect(allowed)
    }

    @Test("機器ごとに数える")
    func countsPerDevice() {
        var limiter = RepeatedConnectionLimiter()
        for offset in 0..<3 {
            _ = limiter.allowsDisconnect(headphones, at: start + TimeInterval(offset))
        }

        let headphonesAllowed = limiter.allowsDisconnect(headphones, at: start + 3)
        let earphonesAllowed = limiter.allowsDisconnect(earphones, at: start + 3)
        #expect(!headphonesAllowed)
        #expect(earphonesAllowed)
    }

    @Test("記録を消すと、また0から数える")
    func resetClearsHistory() {
        var limiter = RepeatedConnectionLimiter()
        for offset in 0..<3 {
            _ = limiter.allowsDisconnect(headphones, at: start + TimeInterval(offset))
        }
        limiter.reset()

        let allowed = limiter.allowsDisconnect(headphones, at: start + 3)
        #expect(allowed)
    }
}
