import Foundation
import Testing
@testable import Baton

/// AppSettings のテスト。保存先は、テストごとに専用の UserDefaults を使う
@MainActor
struct AppSettingsTests {
    let suiteName = "AppSettingsTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    @Test("一度も切り替えていなければ、ロック・スリープはオン、画面の消灯はオフ、再生中は切断しない")
    func initialValues() {
        let settings = AppSettings(defaults: defaults)

        #expect(settings.disconnects(on: .screenLock))
        #expect(settings.disconnects(on: .sleep))
        #expect(!settings.disconnects(on: .displaySleep))
        #expect(settings.keepsConnectionWhilePlaying)
    }

    @Test("初期値は保存しない（ユーザーが切り替えたものだけを保存する）")
    func doesNotSaveInitialValues() {
        _ = AppSettings(defaults: defaults)

        // persistentDomain は、保存した値だけを返す（register で登録した初期値は含まない）
        let saved = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(saved.isEmpty)
    }

    @Test("切り替えた値は保存され、作り直しても残る（アプリの再起動）")
    func persistsChanges() {
        let settings = AppSettings(defaults: defaults)
        settings.disconnectsOnScreenLock = false
        settings.disconnectsOnDisplaySleep = true
        settings.keepsConnectionWhilePlaying = false

        let reloaded = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(!reloaded.disconnects(on: .screenLock))
        #expect(reloaded.disconnects(on: .sleep))
        #expect(reloaded.disconnects(on: .displaySleep))
        #expect(!reloaded.keepsConnectionWhilePlaying)
    }
}
