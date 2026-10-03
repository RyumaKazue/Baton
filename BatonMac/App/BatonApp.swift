import SwiftUI

/// アプリの入り口。
/// Baton はメニューバーに常駐するアプリなので、ウィンドウ（WindowGroup）は持たず、MenuBarExtra だけを置く。
/// Dock にアイコンを出さない設定は、Info.plist の LSUIElement（ビルド設定 INFOPLIST_KEY_LSUIElement）で行っている。
@main
struct BatonApp: App {
    // アプリ全体で1つだけ必要な状態は、ここで作って画面に渡す
    @State private var loginItem = LoginItemController()

    var body: some Scene {
        MenuBarExtra("Baton", systemImage: "headphones") {
            MenuContentView()
                .environment(loginItem)
        }
        // .window：メニューを普通のメニューではなく、小さなウィンドウ（ポップオーバー）として表示する。
        // 今後、機器ごとの接続状態やボタンを並べるため、自由にレイアウトできるこちらを使う。
        .menuBarExtraStyle(.window)
    }
}
