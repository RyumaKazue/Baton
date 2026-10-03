import BatonKit
import SwiftUI

/// Baton で管理する機器を登録・解除する画面（メニューの「機器を登録・解除…」から開くウィンドウ）。
///
/// ペアリング済みの音声機器を一覧にし、スイッチで登録・解除する。
/// 登録しているのにペアリング済みの一覧に見つからない機器（Mac とのペアリングを解除した機器など）も、解除できるように表示する。
struct DeviceRegistrationView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.pairedDevices.isEmpty && missingRegisteredDevices.isEmpty {
                emptyState
            } else {
                List {
                    Section("ペアリング済みの音声機器") {
                        ForEach(store.pairedDevices) { device in
                            pairedDeviceRow(device)
                        }
                    }
                    if !missingRegisteredDevices.isEmpty {
                        Section("見つからない登録機器") {
                            ForEach(missingRegisteredDevices) { device in
                                missingDeviceRow(device)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("登録した機器が、メニューに表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("一覧を更新", systemImage: "arrow.clockwise") {
                    store.refreshPairedDevices()
                }
            }
            .padding(12)
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            store.refreshPairedDevices()
        }
    }

    /// 登録しているが、ペアリング済みの一覧に見つからない機器
    private var missingRegisteredDevices: [RegisteredDevice] {
        store.registeredDevices.filter { store.isMissingFromPairedDevices($0.address) }
    }

    private func pairedDeviceRow(_ device: BluetoothDeviceInfo) -> some View {
        Toggle(isOn: Binding(
            get: { store.isRegistered(device.address) },
            set: { isOn in
                if isOn {
                    store.register(device)
                } else {
                    store.unregister(device.address)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(store.isConnected(device.address) ? "この Mac に接続中" : "未接続")
                    .font(.caption)
                    .foregroundStyle(store.isConnected(device.address) ? .green : .secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func missingDeviceRow(_ device: RegisteredDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text("この Mac とペアリングされていません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("登録を解除") {
                store.unregister(device.address)
            }
        }
    }

    /// 機器が1台も見つからないとき。
    /// Bluetooth の権限がないと、エラーにならずに一覧が空になる（docs/spikes/iobluetooth.md 4.3）ので、その可能性も案内する
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("ペアリング済みの音声機器が見つかりません")
                .font(.headline)
            Text("システム設定の Bluetooth で、機器がこの Mac とペアリングされているか確認してください。ペアリング済みなのに表示されない場合は、Baton に Bluetooth の使用が許可されているか確認してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DeviceRegistrationView()
        .environment(DeviceStore(bluetooth: MockBluetoothService()))
}
