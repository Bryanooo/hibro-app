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
