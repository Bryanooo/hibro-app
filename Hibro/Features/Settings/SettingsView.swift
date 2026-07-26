import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingLogout = false
    @State private var confirmingServerChange = false

    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("用户", value: model.currentUser?.displayName ?? "—")
                LabeledContent("账号", value: model.currentUser?.username ?? "—")
                LabeledContent(
                    "角色",
                    value: model.currentUser?.roles.joined(separator: " · ") ?? "—"
                )
            }

            Section("Hibro Core") {
                LabeledContent("地址") {
                    Text(model.isDemoMode ? "演示模式" : model.serverURLText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(
                    "连接安全",
                    value: model.isDemoMode
                        ? "演示"
                        : model.serverURL?.scheme == "https"
                            ? "HTTPS"
                            : "局域网调试"
                )
                LabeledContent(
                    "API",
                    value: model.bootstrap?.apiVersion ?? "—"
                )
                LabeledContent(
                    "实时连接",
                    value: model.isDemoMode ? "演示" : "SSE"
                )
                Button {
                    Task { await model.refreshFromUser() }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    confirmingServerChange = true
                } label: {
                    Label("更换 Hibro Core", systemImage: "server.rack")
                }
            }

            Section("通知") {
                HStack {
                    Label("Bark Push", systemImage: "bell.badge")
                    Spacer()
                    Text("等待 Core 接入")
                        .foregroundStyle(.secondary)
                }
                Text("后续由 Core 统一发送 Bark 通知，App 已支持 hibro:// 深度链接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("安全") {
                Label("OAuth 2.0 + PKCE", systemImage: "lock.shield")
                Label("Refresh Token 存储在 Keychain", systemImage: "key")
                Label("App 不保存 Core 密码", systemImage: "checkmark.seal")
            }

            Section {
                Button("退出登录", role: .destructive) {
                    confirmingLogout = true
                }
            }

            Section {
                HStack {
                    Text("Hibro App")
                    Spacer()
                    Text("0.1.0 (1)").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .confirmationDialog(
            "确定退出 Hibro？",
            isPresented: $confirmingLogout,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) { model.logout() }
        } message: {
            Text("本机保存的 OAuth Token 会从 Keychain 删除。")
        }
        .confirmationDialog(
            "更换 Hibro Core？",
            isPresented: $confirmingServerChange,
            titleVisibility: .visible
        ) {
            Button("继续") { model.logout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前 Token 将被删除，随后可以测试并登录新的 Core 地址。")
        }
    }
}
