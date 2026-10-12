import BatonKit
import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 他の Mac での接続状態（フェーズ6）や切り替え（フェーズ7）は、この画面に追加していく。
struct MenuContentView: View {
    /// BatonApp で作って渡している、ログイン項目の状態
    @Environment(LoginItemStore.self) private var loginItemStore
    /// BatonApp で作って渡している、登録機器と接続状態
    @Environment(DeviceStore.self) private var deviceStore
    /// BatonApp で作って渡している、アプリの設定
    @Environment(AppSettings.self) private var appSettings
    /// BatonApp で作って渡している、スリープ時の切断と復帰時の再接続
    @Environment(SleepHandler.self) private var sleepHandler
    /// ウィンドウ（登録画面）を開くための機能
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Baton")
                        .font(.headline)
                    Text(Self.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if BluetoothServiceFactory.usesMock {
                    // 本物のイヤホンを操作していないことが一目で分かるようにする
                    Text("ダミーの Bluetooth で動作中")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            registeredDevicesSection

            if BluetoothServiceFactory.usesMock {
                mockSleepSection
            }

            Divider()

            leaveSettingsSection

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
        .frame(width: 320, alignment: .leading)
        .onAppear {
            // システム設定で直接変えられていることもあるので、表示のたびに取り直す
            loginItemStore.refresh()
            // Bluetooth の通知が届いていないことがあるので（#51）、開くたびに接続状態を読み直す
            deviceStore.resync()
        }
        .onDisappear {
            // 接続・切断に失敗したときのメッセージは、メニューを閉じたら消す（一度見たら残さない）
            deviceStore.clearErrorMessages()
        }
    }

    /// アプリのバージョン（例：v0.1）。Info.plist の CFBundleShortVersionString（ビルド設定 MARKETING_VERSION）から読む
    private static var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "v\(shortVersion)"
    }

    /// 登録機器の一覧と、登録画面を開くボタン
    @ViewBuilder
    private var registeredDevicesSection: some View {
        if deviceStore.registeredDevices.isEmpty {
            Text("登録した機器はありません")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(deviceStore.registeredDevices) { device in
                    DeviceRowView(device: device)
                }
            }
        }

        Button("機器を登録・解除…") {
            openWindow(id: WindowID.deviceRegistration)
            // Dock に出ないアプリなので、開いたウィンドウを前面に出すために、アプリを前面にする
            NSApplication.shared.activate()
        }
    }

    /// ダミーのモードでだけ表示する、離れる・戻るを再現するボタン（実際にスリープやロックをせずに動きを確かめるため）
    private var mockSleepSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("再現")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("ロック") {
                    Task { await sleepHandler.handleUserLeaving(reason: .screenLock) }
                }
                Button("スリープ") {
                    Task { await sleepHandler.handleUserLeaving(reason: .sleep) }
                }
                Button("画面の消灯") {
                    Task { await sleepHandler.handleUserLeaving(reason: .displaySleep) }
                }
                Button("戻る") {
                    Task { await sleepHandler.handleUserReturned() }
                }
            }
        }
        .controlSize(.small)
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
    /// 名前を横いっぱいに広げて、スイッチを右端（機器の「接続」「切断」ボタンと同じ列）にそろえる
    private func settingSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    /// 「ログイン時に起動」のオン・オフと、その補足の表示
    @ViewBuilder
    private var loginItemSection: some View {
        settingSwitch("ログイン時に起動", isOn: Binding(
            get: { loginItemStore.isEnabled },
            set: { loginItemStore.setEnabled($0) }
        ))

        if loginItemStore.requiresApproval {
            VStack(alignment: .leading, spacing: 4) {
                Text("システム設定で許可が必要です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("システム設定を開く") {
                    loginItemStore.openSystemSettings()
                }
                .font(.caption)
            }
        }

        if let message = loginItemStore.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    let deviceStore = DeviceStore(bluetooth: MockBluetoothService(), audioOutput: MockAudioOutputService())
    let appSettings = AppSettings()
    return MenuContentView()
        .environment(LoginItemStore())
        .environment(deviceStore)
        .environment(appSettings)
        .environment(SleepHandler(power: MockPowerEventService(), deviceStore: deviceStore, settings: appSettings))
}
