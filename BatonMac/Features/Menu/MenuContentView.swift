import BatonKit
import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 他の Mac での接続状態（フェーズ6）や切り替え（フェーズ7）は、この画面に追加していく。
struct MenuContentView: View {
    /// BatonApp で作って渡している、ログイン項目の状態
    @Environment(LoginItemStore.self) private var loginItemStore
    /// BatonApp で作って渡している、登録機器と接続状態
    @Environment(DeviceStore.self) private var deviceStore
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
            Button("離れる（スリープ・ロック）を再現") {
                Task { await sleepHandler.handleUserLeaving() }
            }
            Button("戻るを再現") {
                Task { await sleepHandler.handleUserReturned() }
            }
        }
        .controlSize(.small)
    }

    /// 「ログイン時に起動」のオン・オフと、その補足の表示
    @ViewBuilder
    private var loginItemSection: some View {
        Toggle("ログイン時に起動", isOn: Binding(
            get: { loginItemStore.isEnabled },
            set: { loginItemStore.setEnabled($0) }
        ))
        .toggleStyle(.switch)

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
    let deviceStore = DeviceStore(bluetooth: MockBluetoothService())
    return MenuContentView()
        .environment(LoginItemStore())
        .environment(deviceStore)
        .environment(SleepHandler(power: MockPowerEventService(), deviceStore: deviceStore))
}
