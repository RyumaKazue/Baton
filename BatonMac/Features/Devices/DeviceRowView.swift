import BatonKit
import SwiftUI

/// メニューに表示する、登録機器1台分の行。
/// 接続状態と、接続・切断のボタン、操作中の表示、失敗したときのメッセージを出す。
struct DeviceRowView: View {
    let device: RegisteredDevice

    @Environment(DeviceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIndicator
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actionButton
            }

            if let message = store.errorMessage(for: device.address) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    // 長いメッセージを省略せず、折り返して全部表示する
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var operation: DeviceOperation? {
        store.operation(for: device.address)
    }

    private var isConnected: Bool {
        store.isConnected(device.address)
    }

    /// 左端の印：操作中はくるくる回る表示、それ以外は接続状態の丸
    @ViewBuilder
    private var statusIndicator: some View {
        if operation != nil {
            ProgressView()
                .controlSize(.small)
        } else {
            Circle()
                .fill(isConnected ? .green : .gray.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch operation {
        case .connecting:
            return "接続しています…"
        case .disconnecting:
            return "切断しています…"
        case nil:
            return isConnected ? "この Mac に接続中" : "未接続"
        }
    }

    /// 接続中なら「切断」、未接続なら「接続」。操作中は押せない
    private var actionButton: some View {
        Button(isConnected ? "切断" : "接続") {
            // ボタンの処理は async にできないので、Task の中で await する
            Task {
                if isConnected {
                    await store.disconnect(device.address)
                } else {
                    await store.connect(device.address)
                }
            }
        }
        .controlSize(.small)
        .disabled(operation != nil)
    }
}
