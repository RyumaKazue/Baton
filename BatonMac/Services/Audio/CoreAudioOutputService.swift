import BatonKit
import CoreAudio

/// CoreAudio を使う、本物の AudioOutputService。
///
/// CoreAudio は C の API で、「どの対象（AudioObjectID）の、どの項目（セレクタ）を読み書きするか」を
/// AudioObjectPropertyAddress で指定して、AudioObjectGetPropertyData / AudioObjectSetPropertyData を呼ぶ。
/// - Mac 全体の設定（今の出力先、機器の一覧）は、システムの対象（kAudioObjectSystemObject）に聞く
/// - 機器ごとの情報（UID、出力があるか）は、その機器の AudioDeviceID に聞く
///
/// Bluetooth の出力先は、UID にアドレスが入っている（`08-F0-B6-F4-7F-FB:output`）ので、アドレスで見分ける。
@MainActor
final class CoreAudioOutputService: AudioOutputService {
    func switchDefaultOutput(to address: BluetoothAddress) -> AudioOutputSwitchResult {
        guard let deviceID = Self.outputDeviceID(for: address) else {
            return .notFound
        }
        if Self.defaultOutputDeviceID() == deviceID {
            return .alreadyDefault
        }

        var propertyAddress = Self.systemProperty(kAudioHardwarePropertyDefaultOutputDevice)
        var newDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &newDeviceID
        )
        return status == noErr ? .switched : .failed(status: status)
    }

    func isPlaying(on address: BluetoothAddress) -> Bool {
        guard let deviceID = Self.outputDeviceID(for: address) else {
            return false  // 出力先の一覧にない ＝ 音は出ていない
        }
        // どれかのアプリがその機器で音を出し入れしていると、0 以外になる
        var propertyAddress = Self.systemProperty(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    // MARK: - CoreAudio への問い合わせ

    /// その Bluetooth 機器の、出力の AudioDeviceID。出力先の一覧になければ nil
    private static func outputDeviceID(for address: BluetoothAddress) -> AudioDeviceID? {
        outputDeviceIDs().first { bluetoothAddress(of: $0) == address }
    }

    /// 今の出力先
    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = systemProperty(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    /// 音を出せる機器の一覧（マイクなど、入力だけの機器は含まない）
    private static func outputDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = systemProperty(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size) == noErr else {
            return []
        }
        // 一覧の大きさ（バイト数）を先に聞いてから、その数だけの入れ物を用意して読む
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs.filter(hasOutputStreams)
    }

    /// 出力の向きのストリーム（音の通り道）を持つか ＝ 音を出せる機器か
    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size)
        return status == noErr && size > 0
    }

    /// 機器の UID から取り出した Bluetooth アドレス。Bluetooth の機器でなければ nil
    private static func bluetoothAddress(of deviceID: AudioDeviceID) -> BluetoothAddress? {
        var propertyAddress = systemProperty(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &uid) == noErr,
              let uid = uid?.takeRetainedValue() else {
            return nil
        }
        return BluetoothAddress(audioDeviceUID: uid as String)
    }

    /// Mac 全体（グローバル）の項目を指す AudioObjectPropertyAddress
    private static func systemProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
