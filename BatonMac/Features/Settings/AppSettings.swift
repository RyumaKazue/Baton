import Foundation
import Observation

/// アプリの設定。Mac 全体で1つ持ち、UserDefaults に保存して、アプリを再起動しても残す（仕様書 13.3）。
///
/// - 今は「離れるときに、どのきっかけで切断するか」と「再生中は切断しないか」を持つ。v0.2 の設定（表示名、応答の待ち時間、
///   切断時の通知）も、ここに足していく
/// - ログイン時の起動は、ここではなく LoginItemStore が持つ（値が UserDefaults ではなく macOS の側にあるため）
/// - 画面（メニューのスイッチ）が値を読み書きし、SleepHandler が切断するかの判断に使う
///
/// SwiftUI の `@AppStorage` は View の中で使うためのもので、画面の外（SleepHandler）からは使えないため、
/// `@Observable` のクラスに持たせ、UserDefaults には自分で読み書きする。
@MainActor
@Observable
final class AppSettings {
    /// 画面をロックしたときに切断する
    var disconnectsOnScreenLock: Bool {
        didSet { defaults.set(disconnectsOnScreenLock, forKey: Key.disconnectsOnScreenLock) }
    }
    /// スリープに入るときに切断する
    var disconnectsOnSleep: Bool {
        didSet { defaults.set(disconnectsOnSleep, forKey: Key.disconnectsOnSleep) }
    }
    /// 画面が消えたとき（ディスプレイのスリープ）に切断する
    var disconnectsOnDisplaySleep: Bool {
        didSet { defaults.set(disconnectsOnDisplaySleep, forKey: Key.disconnectsOnDisplaySleep) }
    }
    /// 音声の再生中は、ロックと画面の消灯では切断しない（音が止まったら切断する）。スリープでは切断する
    var keepsConnectionWhilePlaying: Bool {
        didSet { defaults.set(keepsConnectionWhilePlaying, forKey: Key.keepsConnectionWhilePlaying) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// UserDefaults に保存するときのキー
    enum Key {
        static let disconnectsOnScreenLock = "disconnectsOnScreenLock"
        static let disconnectsOnSleep = "disconnectsOnSleep"
        static let disconnectsOnDisplaySleep = "disconnectsOnDisplaySleep"
        static let keepsConnectionWhilePlaying = "keepsConnectionWhilePlaying"
    }

    /// 一度も切り替えていないときの値。
    /// 画面の消灯は、画面を消したまま音楽を聴いていることがあるので、最初はオフにする
    static let initialValues: [String: Any] = [
        Key.disconnectsOnScreenLock: true,
        Key.disconnectsOnSleep: true,
        Key.disconnectsOnDisplaySleep: false,
        Key.keepsConnectionWhilePlaying: true,
    ]

    /// - Parameter defaults: 保存先。テストでは、テスト専用の UserDefaults を渡す
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 保存した値がないときの代わりを、メモリの上にだけ登録する（ディスクには保存しない）。
        // 保存するのは、ユーザーが切り替えたとき（didSet）だけ
        defaults.register(defaults: Self.initialValues)

        // init の中で値を入れても didSet は呼ばれないので、読んだ値を書き戻すことはない
        disconnectsOnScreenLock = defaults.bool(forKey: Key.disconnectsOnScreenLock)
        disconnectsOnSleep = defaults.bool(forKey: Key.disconnectsOnSleep)
        disconnectsOnDisplaySleep = defaults.bool(forKey: Key.disconnectsOnDisplaySleep)
        keepsConnectionWhilePlaying = defaults.bool(forKey: Key.keepsConnectionWhilePlaying)
    }

    /// その理由で離れたときに、切断するか
    func disconnects(on reason: LeaveReason) -> Bool {
        switch reason {
        case .screenLock: disconnectsOnScreenLock
        case .sleep: disconnectsOnSleep
        case .displaySleep: disconnectsOnDisplaySleep
        }
    }
}
