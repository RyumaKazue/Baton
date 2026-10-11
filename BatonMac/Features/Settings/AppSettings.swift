import Foundation
import Observation

/// アプリの設定。Mac 全体で1つ持ち、UserDefaults に保存して、アプリを再起動しても残す（仕様書 13.3）。
///
/// - 今は「離れるときに、どのきっかけで切断するか」と「再生中は、音が止まってから切断するか」を持つ。v0.2 の設定（表示名、応答の待ち時間、
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
    /// 再生中は、音が止まってから切断する（ロックと画面の消灯のとき。音が止まって約30秒たったら切断する）。
    /// オフなら、再生中でもすぐ切断する。スリープでは、どちらでもすぐ切断する。
    /// 「離れるときに切断」の他のスイッチとそろえて、オン＝切断する側の言い方にしている（オン＝切断しない、だと逆になって分かりにくいため）
    var waitsForAudioToStop: Bool {
        didSet { defaults.set(waitsForAudioToStop, forKey: Key.waitsForAudioToStop) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// UserDefaults に保存するときのキー
    enum Key {
        static let disconnectsOnScreenLock = "disconnectsOnScreenLock"
        static let disconnectsOnSleep = "disconnectsOnSleep"
        static let disconnectsOnDisplaySleep = "disconnectsOnDisplaySleep"
        static let waitsForAudioToStop = "waitsForAudioToStop"
    }

    /// 一度も切り替えていないときの値。
    /// 画面の消灯は、画面を消したまま音楽を聴いていることがあるので、最初はオフにする
    static let initialValues: [String: Any] = [
        Key.disconnectsOnScreenLock: true,
        Key.disconnectsOnSleep: true,
        Key.disconnectsOnDisplaySleep: false,
        Key.waitsForAudioToStop: true,
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
        waitsForAudioToStop = defaults.bool(forKey: Key.waitsForAudioToStop)
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
