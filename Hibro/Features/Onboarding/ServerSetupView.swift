import SwiftUI

struct ServerSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var serverAddress = ""
    @State private var connectionVerified = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 36)
                HibroMark(size: 76)
                VStack(spacing: 10) {
                    Text("连接你的 Hibro Core")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("一个 App，连接你的所有 Node 与 Agent。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("CORE 地址")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        AppModel.defaultServerURL.absoluteString,
                        text: $serverAddress
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .font(.body.monospaced())
                        .padding(15)
                        .background(
                            HibroTheme.panelStrong,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                        .onChange(of: serverAddress) {
                            connectionVerified = false
                        }

                    Button {
                        Task {
                            connectionVerified = await model.testServerConnection(
                                serverAddress: serverAddress
                            )
                        }
                    } label: {
                        Label(
                            connectionVerified ? "连接正常" : "测试连接",
                            systemImage: connectionVerified
                                ? "checkmark.circle.fill"
                                : "network"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(connectionVerified ? .green : HibroTheme.accent)
                    .disabled(model.isWorking || serverAddress.nilIfBlank == nil)

                    Button {
                        Task { await model.login(serverAddress: serverAddress) }
                    } label: {
                        HStack {
                            if model.isWorking {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "lock.shield")
                            }
                            Text(model.isWorking ? "正在连接…" : "安全登录")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HibroTheme.accent)
                    .foregroundStyle(.black)
                    .disabled(model.isWorking || serverAddress.nilIfBlank == nil)

                    Label(
                        "登录将在系统浏览器中完成。App 不会获取或保存你的 Core 密码。",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label(
                        "推荐 HTTPS；同一 Wi-Fi 联调可使用 Mac 的私有地址，例如 http://192.168.1.220:17400。",
                        systemImage: "wifi"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 520)
                .hibroPanel()

                #if DEBUG
                Button("查看演示界面") { model.loadDemo() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                #endif
            }
            .padding(24)
        }
        .onAppear {
            if serverAddress.isEmpty {
                serverAddress = model.serverURLText
            }
        }
    }
}
