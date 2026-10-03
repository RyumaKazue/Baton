import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 登録機器の一覧（フェーズ3）や接続状態（フェーズ6）は、この画面に追加していく。
struct MenuContentView: View {
    /// BatonApp で作って渡している、ログイン項目の状態
    @Environment(LoginItemController.self) private var loginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Baton")
                .font(.headline)

            Divider()

            loginItemSection

            Divider()

            Button("Baton を終了") {
                // Dock にアイコンがないので、アプリを終了する手段はこのボタンだけになる
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280, alignment: .leading)
        .onAppear {
            // システム設定で直接変えられていることもあるので、表示のたびに取り直す
            loginItem.refresh()
        }
    }

    /// 「ログイン時に起動」のオン・オフと、その補足の表示
    @ViewBuilder
    private var loginItemSection: some View {
        Toggle("ログイン時に起動", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))
        .toggleStyle(.switch)

        if loginItem.requiresApproval {
            VStack(alignment: .leading, spacing: 4) {
                Text("システム設定で許可が必要です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("システム設定を開く") {
                    loginItem.openSystemSettings()
                }
                .font(.caption)
            }
        }

        if let message = loginItem.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    MenuContentView()
        .environment(LoginItemController())
}
