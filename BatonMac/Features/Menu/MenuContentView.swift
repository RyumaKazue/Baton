import SwiftUI

/// メニューバーのアイコンをクリックしたときに表示する画面。
/// 登録機器の一覧（フェーズ3）や接続状態（フェーズ6）は、この画面に追加していく。
struct MenuContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Baton")
                .font(.headline)

            Divider()

            Button("Baton を終了") {
                // Dock にアイコンがないので、アプリを終了する手段はこのボタンだけになる
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280, alignment: .leading)
    }
}

#Preview {
    MenuContentView()
}
