import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            HibroTheme.background.ignoresSafeArea()
            switch model.phase {
            case .launching:
                ProgressView("正在恢复 Hibro 会话…")
                    .controlSize(.large)
            case .signedOut, .authenticating:
                ServerSetupView()
            case .connectionUnavailable:
                ConnectionUnavailableView()
            case .signedIn:
                AppShellView()
            }
        }
        .alert(
            "Hibro",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct ConnectionUnavailableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "暂时无法连接 Hibro Core",
                systemImage: "wifi.exclamationmark",
                description: Text(
                    model.connectionMessage
                        ?? "登录信息仍保存在本机，恢复网络后可以直接重试。"
                )
            )
            VStack(spacing: 10) {
                Button {
                    Task { await model.retryInitialConnection() }
                } label: {
                    Label("重新连接", systemImage: "arrow.clockwise")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .tint(HibroTheme.accent)
                .foregroundStyle(.black)

                Button("更换 Core 或退出登录") {
                    model.logout()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }
}
