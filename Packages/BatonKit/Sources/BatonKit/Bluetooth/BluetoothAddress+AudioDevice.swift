extension BluetoothAddress {
    /// CoreAudio の機器の UID から、Bluetooth アドレスを取り出す。
    ///
    /// Bluetooth の音声機器の UID は、アドレスの後ろに向きが付いた形になっている（2026-10-09 にこの Mac で確認）。
    /// - 出力：`08-F0-B6-F4-7F-FB:output`
    /// - 入力（マイク）：`08-F0-B6-F4-7F-FB:input`
    ///
    /// アドレスで始まらない UID（内蔵スピーカーの `BuiltInSpeakerDevice` など）なら `nil` を返す。
    public init?(audioDeviceUID uid: String) {
        // アドレスは区切りを含めて17文字。その後ろは、何もないか「:」で始まる
        let addressLength = 17
        guard uid.count >= addressLength else { return nil }
        let rest = uid.dropFirst(addressLength)
        guard rest.isEmpty || rest.hasPrefix(":") else { return nil }
        self.init(String(uid.prefix(addressLength)))
    }
}
