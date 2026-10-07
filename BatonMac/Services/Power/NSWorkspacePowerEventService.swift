import AppKit
import CoreGraphics

/// NSWorkspace の通知を使う、本物の PowerEventService。
///
/// | macOS の通知 | 知らせる出来事 |
/// |---|---|
/// | willSleepNotification（スリープに入る直前） | onWillSleep |
/// | screensDidWakeNotification（画面が点いた） | onUserReturned |
/// | didWakeNotification（システムが起きた）で、画面も点いているとき | onUserReturned |
///
/// didWakeNotification はダークウェイクでも届く可能性があるため、画面が点いているときだけ知らせる。
/// 画面の通知と重なって2回知らせることがあるが、受け取る側（SleepHandler）は2回目では何もしない。
/// アプリが動いている間ずっと1つだけ使う前提なので、通知の登録は解除していない。
@MainActor
final class NSWorkspacePowerEventService: PowerEventService {
    var onWillSleep: (() -> Void)?
    var onUserReturned: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onWillSleep?()
            }
        })

        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onUserReturned?()
            }
        })

        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Self.isDisplayAwake else { return }  // ダークウェイクでは知らせない
                self?.onUserReturned?()
            }
        })
    }

    /// メインの画面が点いているか
    private static var isDisplayAwake: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }
}
