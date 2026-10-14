import AppKit
import os

/// Baton を起動し直す（#51）。
///
/// 新しい Baton を起動してから、自分（古い Baton）を終了する。Sandbox の中でも動く（2026-10-14 に確認）。
/// 登録機器と設定は UserDefaults にあるので残る。「離れている間か」「戻ったら再接続する機器」などの
/// メモリの上の状態は引き継がない（起動し直すのは、電池切れの深いスリープから起きたときだけなので、
/// そのときはロックを解除しても自動で再接続されない。2026-10-14 にユーザーと決定）
enum AppRelauncher {
    @MainActor
    static func relaunch(reason: String) {
        Logger.app.notice("起動し直す（\(reason, privacy: .public)）")
        let configuration = NSWorkspace.OpenConfiguration()
        // すでに動いていても、新しくもう1つ起動する
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Logger.app.error("新しい Baton を起動できなかった：\(String(describing: error), privacy: .public)")
                    return
                }
                Logger.app.notice("新しい Baton を起動したので、古い方を終了する")
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
