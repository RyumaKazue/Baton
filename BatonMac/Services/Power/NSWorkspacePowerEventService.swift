import AppKit
import CoreGraphics

/// macOS の通知を使う、本物の PowerEventService。
///
/// | macOS の通知 | 知らせる出来事 |
/// |---|---|
/// | willSleepNotification（スリープに入る直前） | onUserLeaving |
/// | com.apple.screenIsLocked（画面をロックした。電源ボタン、⌃⌘Q など） | onUserLeaving |
/// | com.apple.screenIsUnlocked（ロックを解除した） | onUserReturned |
/// | screensDidWakeNotification（画面が点いた）で、ロックされていないとき | onUserReturned |
/// | didWakeNotification（システムが起きた）で、画面が点いていて、ロックされていないとき | onUserReturned |
///
/// - 電源ボタンを押しても、Mac はすぐにはスリープしない（画面が消えてロックされるだけ）。
///   ヘッドホンがつながっている間は自動でもスリープしないので、ロックしたときにも切断する
/// - ロック画面のままや、ダークウェイクでは再接続しないように、「戻ってきた」はロックの解除を基準にする
/// - ロックとロック解除の通知（com.apple.screenIs〜）は、Apple の公式のドキュメントには載っていない通知で、
///   将来の macOS で変わる可能性がある
/// - 同じ出来事を続けて知らせることがあるが、受け取る側（SleepHandler）は2回目では何もしない
/// - アプリが動いている間ずっと1つだけ使う前提なので、通知の登録は解除していない
@MainActor
final class NSWorkspacePowerEventService: PowerEventService {
    var onUserLeaving: (() -> Void)?
    var onUserReturned: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.onUserLeaving?()
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.onUserLeaving?()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.onUserReturned?()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            // ロック画面のままなら、ロックの解除を待つ
            guard !Self.isScreenLocked else { return }
            self?.onUserReturned?()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            // ダークウェイク（画面が消えたまま）やロック画面のままなら、知らせない
            guard Self.isDisplayAwake, !Self.isScreenLocked else { return }
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
