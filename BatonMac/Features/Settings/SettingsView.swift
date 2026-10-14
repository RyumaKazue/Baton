import SwiftUI

/// 設定の画面。メニューの右上の歯車を押すと、メニューの中身がこの画面に切り替わる（#55）。
/// 左上の「戻る」で、機器の一覧に戻る。
struct SettingsView: View {
    /// BatonApp で作って渡している、ログイン項目の状態
    @Environment(LoginItemStore.self) private var loginItemStore
    /// BatonApp で作って渡している、アプリの設定
    @Environment(AppSettings.self) private var appSettings

    /// 「戻る」を押したときの処理（MenuContentView が、機器の一覧に切り替える）
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            leaveSettingsSection

            Divider()

            loginItemSection
        }
        .onAppear {
            // システム設定で直接変えられていることもあるので、表示のたびに取り直す
            loginItemStore.refresh()
        }
    }

    /// 左に「戻る」、真ん中に「設定」
    private var header: some View {
        ZStack {
            Text("設定")
                .font(.headline)
            HStack {
                Button(action: onBack) {
                    Label("戻る", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
    }

    /// 自動で切断する設定。見出しと項目が結び付くように、「いつ切断するか（タイミング）」と
    /// 「再生中のときにどうするか」を、見出しで分けて並べる
    @ViewBuilder
    private var leaveSettingsSection: some View {
        // @Environment で受け取った値から、スイッチに渡す Binding（$settings.〜）を作るために @Bindable にする
        @Bindable var settings = appSettings

        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("自動で切断するタイミング")
            sectionNote("他の端末ですぐ使えるように切断し、戻ってきたらつなぎ直します")
            settingSwitch("画面をロックしたとき", isOn: $settings.disconnectsOnScreenLock)
            settingSwitch("スリープしたとき", isOn: $settings.disconnectsOnSleep)
            settingSwitch("画面が消えたとき", isOn: $settings.disconnectsOnDisplaySleep)
            if !settings.disconnectsOnScreenLock {
                // ヘッドホンがつながっている間は Mac が自動でスリープしないことがあり（仕様書 7）、
                // 電源ボタンで離れても切断されなくなるため
                sectionNote("ヘッドホンがつながっている間は、Mac が自動でスリープしないことがあります")
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("再生中のとき")
            settingSwitch("音が止まるまで待つ", isOn: $settings.waitsForAudioToStop)
            if settings.waitsForAudioToStop {
                sectionNote("ロック・画面の消灯のとき、止まって30秒たってから切断します")
            }
        }
    }

    /// 「ログイン時に起動」のオン・オフと、その補足の表示
    private var loginItemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("起動")
            settingSwitch("ログイン時に起動", isOn: Binding(
                get: { loginItemStore.isEnabled },
                set: { loginItemStore.setEnabled($0) }
            ))

            if loginItemStore.requiresApproval {
                sectionNote("システム設定で許可が必要です")
                Button("システム設定を開く") {
                    loginItemStore.openSystemSettings()
                }
                .font(.caption)
            }

            if let message = loginItemStore.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// 設定のまとまりの見出し（項目と区別できるように太字にする）
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
    }

    /// 設定のまとまりの補足の文（小さく、薄い字）。長い文は折り返す
    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 名前を左端、スイッチを右端に置いたスイッチ。
    /// macOS の標準ではスイッチが名前のすぐ右に付き、名前の長さで位置がずれるので、
    /// 名前を横いっぱいに広げて、スイッチを右端にそろえる
    private func settingSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

#Preview {
    SettingsView(onBack: {})
        .environment(LoginItemStore())
        .environment(AppSettings())
        .padding()
        .frame(width: 320)
}
