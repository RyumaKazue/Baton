import SwiftUI
import os

/// アプリの入り口。
/// Baton はメニューバーに常駐するアプリなので、メインの画面は MenuBarExtra に置く。
/// Dock にアイコンを出さない設定は、Info.plist の LSUIElement（ビルド設定 INFOPLIST_KEY_LSUIElement）で行っている。
@main
struct BatonApp: App {
    // アプリ全体で1つだけ必要な状態は、ここで作って画面に渡す
    @State private var loginItemStore = LoginItemStore()
    @State private var deviceStore: DeviceStore
    @State private var appSettings: AppSettings
    @State private var sleepHandler: SleepHandler
    /// bluetoothd が起動し直したことに気づいて、Baton を起動し直す（#51）
    @State private var daemonWatcher: BluetoothDaemonWatcher

    init() {
        Logger.app.notice("起動（Bluetooth：\(BluetoothServiceFactory.usesMock ? "ダミー" : "本物", privacy: .public)）")
        // BluetoothService は、ここで1回だけ作る（作るたびに Bluetooth の通知が登録されるため）
        let deviceStore = DeviceStore(
            bluetooth: BluetoothServiceFactory.make(),
            audioOutput: AudioOutputServiceFactory.make()
        )
        let appSettings = AppSettings()
        // SleepHandler は DeviceStore と AppSettings を使うので、プロパティの初期値ではなく init の中で作る
        _deviceStore = State(initialValue: deviceStore)
        _appSettings = State(initialValue: appSettings)
        _sleepHandler = State(initialValue: SleepHandler(
            power: NSWorkspacePowerEventService(),
            deviceStore: deviceStore,
            settings: appSettings
        ))

        // 電池切れの深いスリープから起きると bluetoothd が起動し直し、Baton の中の Bluetooth の部品が
        // 機器の情報を正しく持てなくなるので、起動し直す（#51）。ダミーの Bluetooth のとき（テスト、Mock のスキーム）は見張らない
        let daemonWatcher = BluetoothDaemonWatcher()
        daemonWatcher.onRestartNeeded = {
            AppRelauncher.relaunch(reason: "bluetoothd が起動し直した")
        }
        if !BluetoothServiceFactory.usesMock {
            daemonWatcher.start()
        }
        _daemonWatcher = State(initialValue: daemonWatcher)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(loginItemStore)
                .environment(deviceStore)
                .environment(appSettings)
                .environment(sleepHandler)
        } label: {
            // 登録機器の接続状態に合わせて、アイコンが変わる（DeviceStore は @Observable なので、変化に合わせて描き直される）
            MenuBarIcon(summary: deviceStore.connectionSummary)
        }
        // .window：メニューを普通のメニューではなく、小さなウィンドウ（ポップオーバー）として表示する。
        // 機器ごとの接続状態やボタンを並べるため、自由にレイアウトできるこちらを使う。
        .menuBarExtraStyle(.window)

        // 機器の登録・解除の画面。メニューの「機器を登録・解除…」から開く
        Window("機器の登録", id: WindowID.deviceRegistration) {
            DeviceRegistrationView()
                .environment(deviceStore)
        }
        .windowResizability(.contentSize)
    }
}

/// ウィンドウを開くときに使う ID
enum WindowID {
    static let deviceRegistration = "device-registration"
}
