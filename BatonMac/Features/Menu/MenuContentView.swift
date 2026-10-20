import BatonKit
import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 機器の一覧（ふだんの画面）と、設定の画面（SettingsView）を、右上の歯車と「戻る」で切り替える（#55）。
struct MenuContentView: View {
    /// メニューの中に表示する画面
    enum Page {
        /// 機器の一覧と接続・切断（ふだんの画面）
        case devices
        /// 設定
        case settings
    }

    /// BatonApp で作って渡している、登録機器と接続状態
    @Environment(DeviceStore.self) private var deviceStore
    /// BatonApp で作って渡している、スリープ時の切断と復帰時の再接続
    @Environment(SleepHandler.self) private var sleepHandler
    /// ウィンドウ（登録画面）を開くための機能
    @Environment(\.openWindow) private var openWindow

    /// 今表示している画面
    @State private var page: Page

    /// - Parameter initialPage: 最初に表示する画面（ふだんは機器の一覧。プレビューやテストで設定の画面を見るときに変える）
    init(initialPage: Page = .devices) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        Group {
            switch page {
            case .devices:
                devicesPage
            case .settings:
                SettingsView(onBack: { page = .devices })
            }
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .onAppear {
            // Bluetooth の通知が届いていないことがあるので（#51）、開くたびに接続状態を読み直す
            deviceStore.resync()
        }
        .onDisappear {
            // 接続・切断に失敗したときのメッセージは、メニューを閉じたら消す（一度見たら残さない）
            deviceStore.clearErrorMessages()
            // 次に開いたときは、機器の一覧から始める
            page = .devices
        }
    }

    /// 機器の一覧の画面（ふだんの画面）
    private var devicesPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            registeredDevicesSection

            if BluetoothServiceFactory.usesMock {
                mockSleepSection
            }

            Divider()

            Button("\(AppInfo.displayName)を終了") {
                // Dock にアイコンがないので、アプリを終了する手段はこのボタンだけになる
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    /// 左にアプリの名前とバージョン、右上に設定の歯車
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppInfo.displayName)
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
            Spacer()
            Button {
                page = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
            .accessibilityLabel("設定")
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
}

#Preview("機器の一覧") {
    let deviceStore = DeviceStore(bluetooth: MockBluetoothService(), audioOutput: MockAudioOutputService())
    let appSettings = AppSettings()
    return MenuContentView()
        .environment(LoginItemStore())
        .environment(deviceStore)
        .environment(appSettings)
        .environment(SleepHandler(power: MockPowerEventService(), deviceStore: deviceStore, settings: appSettings))
}

#Preview("設定") {
    let deviceStore = DeviceStore(bluetooth: MockBluetoothService(), audioOutput: MockAudioOutputService())
    let appSettings = AppSettings()
    return MenuContentView(initialPage: .settings)
        .environment(LoginItemStore())
        .environment(deviceStore)
        .environment(appSettings)
        .environment(SleepHandler(power: MockPowerEventService(), deviceStore: deviceStore, settings: appSettings))
}
