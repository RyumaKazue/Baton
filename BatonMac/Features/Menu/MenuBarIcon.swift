import SwiftUI

/// メニューバーに出すアイコン。登録機器の接続状態に合わせて、絵を変える（#58。2026-10-16 にユーザーと決定）
///
/// | 状態 | SF Symbols |
/// |---|---|
/// | 未接続 | headphones.slash（斜線入りのヘッドホン） |
/// | 接続中 | headphones |
/// | 接続・切断の途中 | headphones.dots |
struct MenuBarIcon: View {
    let summary: ConnectionSummary

    var body: some View {
        Image(systemName: Self.symbolName(for: summary))
            .accessibilityLabel(Self.accessibilityLabel(for: summary))
    }

    static func symbolName(for summary: ConnectionSummary) -> String {
        switch summary {
        case .disconnected: "headphones.slash"
        case .connected: "headphones"
        case .busy: "headphones.dots"
        }
    }

    /// 読み上げ（VoiceOver）で使う説明
    static func accessibilityLabel(for summary: ConnectionSummary) -> String {
        switch summary {
        case .disconnected: "Baton：未接続"
        case .connected: "Baton：接続中"
        case .busy: "Baton：接続・切断中"
        }
    }
}
