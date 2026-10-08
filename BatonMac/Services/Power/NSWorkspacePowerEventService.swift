import AppKit
import CoreGraphics
import os

/// macOS の通知を使う、本物の PowerEventService。
///
/// | macOS の通知 | 知らせる出来事 |
/// |---|---|
/// | willSleepNotification（スリープに入る直前） | onUserLeaving(.sleep) |
/// | com.apple.screenIsLocked（画面をロックした。電源ボタン、⌃⌘Q など） | onUserLeaving(.screenLock) |
/// | screensDidSleepNotification（画面が消えた） | onUserLeaving(.displaySleep) |
/// | com.apple.screenIsUnlocked（ロックを解除した） | onUserReturned |
/// | screensDidWakeNotification（画面が点いた）で、ロックされていないとき | onUserReturned |
/// | didWakeNotification（システムが起きた）で、画面が点いていて、ロックされていないとき | onUserReturned |
///
/// - 電源ボタンを押しても、Mac はすぐにはスリープしない（画面が消えてロックされるだけ）。
///   ヘッドホンがつながっている間は自動でもスリープしないので、スリープだけでなくロックしたときも「離れた」と知らせる
/// - ロック画面のままや、ダークウェイクでは再接続しないように、「戻ってきた」はロックの解除を基準にする
/// - ロックとロック解除の通知（com.apple.screenIs〜）は、Apple の公式のドキュメントには載っていない通知で、
///   将来の macOS で変わる可能性がある
/// - 切断するかどうかは、ここでは決めない。理由を付けて知らせ、受け取る側（SleepHandler）が設定を見て決める
/// - 同じ出来事を続けて知らせることがあるが、受け取る側（SleepHandler）は2回目では何もしない。
///   たとえば電源ボタンを押すと、ロックと画面の消灯が続けて届く
/// - アプリが動いている間ずっと1つだけ使う前提なので、通知の登録は解除していない
@MainActor
final class NSWorkspacePowerEventService: PowerEventService {
    var onUserLeaving: ((LeaveReason) -> Void)?
    var onUserReturned: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            Logger.power.notice("スリープに入る")
            self?.onUserLeaving?(.sleep)
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            Logger.power.notice("画面がロックされた")
            self?.onUserLeaving?(.screenLock)
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            Logger.power.notice("画面が消えた")
            self?.onUserLeaving?(.displaySleep)
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            Logger.power.notice("ロックが解除された")
            self?.onUserReturned?()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            // ロック画面のままなら、ロックの解除を待つ
            guard !Self.isScreenLocked else {
                Logger.power.notice("画面が点いた（ロック画面のままなので、解除を待つ）")
                return
            }
            Logger.power.notice("画面が点いた")
            self?.onUserReturned?()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            // ダークウェイク（画面が消えたまま）やロック画面のままなら、知らせない
            guard Self.isDisplayAwake, !Self.isScreenLocked else {
                Logger.power.notice("システムが起きた（画面が消えている、またはロック中なので、何もしない）")
                return
            }
            Logger.power.notice("システムが起きた")
            self?.onUserReturned?()
        }
    }

    /// 通知の受け取りを登録する。通知はメインスレッドで受け取る
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        })
    }

    /// メインの画面が点いているか
    private static var isDisplayAwake: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    /// 画面がロックされているか
    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
