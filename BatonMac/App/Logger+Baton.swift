import Foundation
import os

/// Baton のログ。macOS の統合ログに書き込み、Console.app や `log` コマンドで見られる（README「ログを見る」）。
///
/// レベルの使い分け
/// - notice：普段の出来事（接続・切断の結果、スリープ時の処理など）。保存され、後から見られる
/// - error：失敗
/// - debug：細かい情報（重なった通知を無視した、など）。保存されないので、その場で見るときだけ使う
///
/// 機器の名前やアドレスは、自分の Mac の中だけで見るログなので、伏せずに出す（privacy: .public）。
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Kazue.Baton"

    /// アプリ全体（起動など）
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Bluetooth の操作と、変化の通知
    static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    /// 登録機器と、この Mac での接続・切断
    static let devices = Logger(subsystem: subsystem, category: "Devices")
    /// macOS のスリープ・ロック・画面の通知
    static let power = Logger(subsystem: subsystem, category: "Power")
    /// 離れたときの切断と、戻ってきたときの再接続
    static let sleep = Logger(subsystem: subsystem, category: "Sleep")
}
