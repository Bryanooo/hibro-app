import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingLogout = false
    @State private var confirmingServerChange = false
    @State private var showingDisplayNameEditor = false
    @State private var displayNameDraft = ""

    var body: some View {
        Form {
            Section("账号") {
                Button {
                    displayNameDraft = model.greetingName
                    showingDisplayNameEditor = true
                } label: {
                    LabeledContent("称呼", value: model.greetingName)
                }
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
                    "接口版本",
                    value: model.bootstrap?.apiVersion ?? "—"
                )
                LabeledContent(
                    "服务访问",
                    value: model.isDemoMode
                        ? "演示"
                        : model.connectivity.apiState.title
                )
                LabeledContent(
                    "实时同步",
                    value: model.isDemoMode
                        ? "演示"
                        : model.connectivity.realtimeState.title
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

            Section("外观") {
                Picker(
                    "显示模式",
                    selection: Binding(
                        get: { model.appearance },
                        set: { model.setAppearance($0) }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
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
        .alert("修改称呼", isPresented: $showingDisplayNameEditor) {
            TextField("例如 Bryan", text: $displayNameDraft)
                .textInputAutocapitalization(.words)
            Button("取消", role: .cancel) {}
            Button("保存") {
                Task {
                    _ = await model.updateDisplayName(displayNameDraft)
                }
            }
            .disabled(
                displayNameDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
        } message: {
            Text("称呼会保存到当前 Hibro Core 账号，并显示在首页问候语中。")
        }
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
