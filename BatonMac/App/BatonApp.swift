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
    @State private var sleepHandler: SleepHandler

    init() {
        Logger.app.notice("起動（Bluetooth：\(BluetoothServiceFactory.usesMock ? "ダミー" : "本物", privacy: .public)）")
        // BluetoothService は、ここで1回だけ作る（作るたびに Bluetooth の通知が登録されるため）
        let deviceStore = DeviceStore(bluetooth: BluetoothServiceFactory.make())
        // SleepHandler は DeviceStore を使うので、プロパティの初期値ではなく init の中で作る
        _deviceStore = State(initialValue: deviceStore)
        _sleepHandler = State(initialValue: SleepHandler(power: NSWorkspacePowerEventService(), deviceStore: deviceStore))
    }

    var body: some Scene {
        MenuBarExtra("Baton", systemImage: "headphones") {
            MenuContentView()
                .environment(loginItemStore)
                .environment(deviceStore)
                .environment(sleepHandler)
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
