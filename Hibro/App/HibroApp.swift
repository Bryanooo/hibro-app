import SwiftUI

@main
struct HibroApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            qaViewport
        }
    }

    @ViewBuilder
    private var qaViewport: some View {
        let content = RootView()
            .environment(model)
            .tint(HibroTheme.accent)
            .preferredColorScheme(.dark)
            .onOpenURL { model.handleDeepLink($0) }
            .onChange(of: scenePhase) {
                switch scenePhase {
                case .active:
                    model.resumeRealtimeSync()
                case .background:
                    model.suspendRealtimeSync()
                default:
                    break
                }
            }

        if let width = QALaunchConfiguration.viewportWidth {
            ZStack(alignment: .leading) {
                Color.black.ignoresSafeArea()
                content
                    .frame(width: width)
                    .environment(
                        \.horizontalSizeClass,
                        QALaunchConfiguration.horizontalSizeClass == .compact
                            ? .compact
                            : .regular
                    )
            }
        } else {
            content
        }
    }
}
