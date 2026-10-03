import Observation
import ServiceManagement

/// ログイン時の自動起動（システム設定の「ログイン項目」への登録）を扱う。
///
/// macOS 13 から使える SMAppService を使う。`SMAppService.mainApp` は「このアプリ自身」を表し、
/// register() でログイン項目に登録、unregister() で解除する。
@Observable
final class LoginItemController {
    /// 今の登録状態。画面はこの値を見て表示を切り替える
    private(set) var status: SMAppService.Status
    /// 登録・解除に失敗したときに表示するメッセージ
    private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        status = service.status
    }

    /// ログイン時に起動する設定になっているか
    var isEnabled: Bool {
        status == .enabled
    }

    /// 登録はしたが、ユーザーがシステム設定で許可していない状態か
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// ログイン時の自動起動をオン・オフする
    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = enabled
                ? "ログイン項目に登録できませんでした"
                : "ログイン項目から削除できませんでした"
        }
        refresh()
    }

    /// 登録状態を取り直す。
    /// ユーザーがシステム設定で直接オン・オフすることもあるので、メニューを開いたときなどに呼ぶ
    func refresh() {
        status = service.status
    }

    /// システム設定の「ログイン項目」を開く（ユーザーの許可が必要なとき用）
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
