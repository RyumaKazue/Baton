import Foundation

/// 利用者に見せるアプリの名前（#70）。
/// Mac の言語に合わせて、InfoPlist.xcstrings で出し分ける（日本語：オーディオ機器自動接続、英語：AutoConnect）。
/// コードの中の名前（Baton、BatonMac、BatonKit など）とは別で、画面には Baton を出さない。
enum AppInfo {
    /// 表示名。Info.plist の CFBundleDisplayName を、Mac の言語に合わせた値で読む
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "AutoConnect"
    }
}
