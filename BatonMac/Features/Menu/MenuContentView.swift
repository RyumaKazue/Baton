import BatonKit
import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 登録機器の一覧（フェーズ3）や接続状態（フェーズ6）は、この画面に追加していく。
struct MenuContentView: View {
    /// BatonApp で作って渡している、ログイン項目の状態
    @Environment(LoginItemStore.self) private var loginItemStore
    /// BatonApp で作って渡している、登録機器と接続状態
    @Environment(DeviceStore.self) private var deviceStore
    /// ウィンドウ（登録画面）を開くための機能
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Baton")
                    .font(.headline)
                if BluetoothServiceFactory.usesMock {
                    // 本物のイヤホンを操作していないことが一目で分かるようにする
                    Text("ダミーの Bluetooth で動作中")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            registeredDevicesSection

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
            loginItemStore.refresh()
        }
    }

    /// 登録機器の一覧と、登録画面を開くボタン。
    /// 接続・切断のボタンは #20 で追加する
    @ViewBuilder
    private var registeredDevicesSection: some View {
        if deviceStore.registeredDevices.isEmpty {
            Text("登録した機器はありません")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(deviceStore.registeredDevices) { device in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(deviceStore.isConnected(device.address) ? .green : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(device.name)
                            .lineLimit(1)
                        Spacer()
                        Text(deviceStore.isConnected(device.address) ? "接続中" : "未接続")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Button("機器を登録・解除…") {
            openWindow(id: WindowID.deviceRegistration)
            // Dock に出ないアプリなので、開いたウィンドウを前面に出すために、アプリを前面にする
            NSApplication.shared.activate()
        }
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
    MenuContentView()
        .environment(LoginItemStore())
        .environment(DeviceStore(bluetooth: MockBluetoothService()))
}
