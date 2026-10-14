import Testing
@testable import BatonKit

/// bluetoothd が起動し直したことを見分ける判断のテスト。
/// `#expect` の中では値を書き換える関数を呼べないので、答えをいったん変数に入れて確かめる
struct BluetoothDaemonRestartDetectorTests {
    @Test("resetting の後に poweredOn になったら、起動し直す")
    func relaunchesAfterReset() {
        var detector = BluetoothDaemonRestartDetector()
        let answers = [
            detector.shouldRelaunch(on: .resetting, uptime: 100),
            detector.shouldRelaunch(on: .poweredOn, uptime: 102),
        ]
        #expect(answers == [false, true])
    }

    @Test("起動したときの poweredOn では、起動し直さない")
    func doesNotRelaunchOnFirstPowerOn() {
        var detector = BluetoothDaemonRestartDetector()
        let answer = detector.shouldRelaunch(on: .poweredOn, uptime: 1)
        #expect(!answer)
    }

    @Test("ユーザーが Bluetooth をオフ → オンにしたときは、起動し直さない")
    func doesNotRelaunchOnUserToggle() {
        var detector = BluetoothDaemonRestartDetector()
        let answers = [
            detector.shouldRelaunch(on: .poweredOn, uptime: 1),
            detector.shouldRelaunch(on: .other, uptime: 100),      // poweredOff
            detector.shouldRelaunch(on: .poweredOn, uptime: 105),
        ]
        #expect(answers == [false, false, false])
    }

    @Test("resetting の後に一度オフになっても、poweredOn になったら起動し直す")
    func relaunchesAfterResetEvenIfPoweredOffInBetween() {
        var detector = BluetoothDaemonRestartDetector()
        let answers = [
            detector.shouldRelaunch(on: .resetting, uptime: 100),
            detector.shouldRelaunch(on: .other, uptime: 101),
            detector.shouldRelaunch(on: .poweredOn, uptime: 110),
        ]
        #expect(answers == [false, false, true])
    }

    @Test("起動してから決めた時間がたっていなければ、起動し直さない（繰り返しを防ぐ）")
    func doesNotRelaunchRightAfterLaunch() {
        var detector = BluetoothDaemonRestartDetector(minimumUptime: 30)
        let answers = [
            detector.shouldRelaunch(on: .resetting, uptime: 5),
            detector.shouldRelaunch(on: .poweredOn, uptime: 10),
        ]
        #expect(answers == [false, false])
    }

    @Test("一度起動し直すと判断したら、次の resetting までは起動し直さない")
    func relaunchesOncePerReset() {
        var detector = BluetoothDaemonRestartDetector()
        let answers = [
            detector.shouldRelaunch(on: .resetting, uptime: 100),
            detector.shouldRelaunch(on: .poweredOn, uptime: 102),
            detector.shouldRelaunch(on: .poweredOn, uptime: 103),
        ]
        #expect(answers == [false, true, false])
    }
}
