import SwiftUI

private enum ShellRoute: Hashable {
    case inbox(String)
    case conversation(String)
    case run(String)
}

struct AppShellView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @State private var widePath = NavigationPath()
    @State private var homePath = NavigationPath()
    @State private var inboxPath = NavigationPath()
    @State private var runsPath = NavigationPath()
    @State private var morePath = NavigationPath()

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactShell
            } else {
                wideShell
            }
        }
        .onChange(of: model.section) {
            if horizontalSizeClass != .compact {
                widePath = NavigationPath()
            }
        }
        .onChange(of: model.selectedConversationID) {
            guard model.section == .more,
                  let id = model.selectedConversationID
            else { return }
            show(.conversation(id))
        }
        .onChange(of: model.highlightedRunID) {
            guard model.section == .runs,
                  let id = model.highlightedRunID
            else { return }
            show(.run(id))
        }
        .onChange(of: model.selectedInboxItemID) {
            guard model.section == .inbox,
                  let id = model.selectedInboxItemID
            else { return }
            show(.inbox(id))
        }
    }

    private var sectionBinding: Binding<AppSection> {
        Binding(
            get: { model.section },
            set: { model.section = $0 }
        )
    }

    private var compactShell: some View {
        TabView(selection: sectionBinding) {
            compactTab(.home, path: $homePath) {
                HomeView()
            }
            compactTab(.inbox, path: $inboxPath) {
                InboxView()
            }
            compactTab(.runs, path: $runsPath) {
                RunsView()
            }
            compactTab(.more, path: $morePath) {
                MoreView()
            }
        }
    }

    private var wideShell: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List {
                Section("工作") {
                    navigationRow(.home)
                    navigationRow(.inbox)
                    navigationRow(.runs)
                }
                Section("资源") {
                    navigationRow(.more)
                }
                if model.isDemoMode {
                    Section {
                        Label("演示数据", systemImage: "sparkles")
                            .foregroundStyle(HibroTheme.orange)
                    }
                }
            }
            .navigationTitle("Hibro")
            .safeAreaInset(edge: .top) {
                identityHeader
            }
        } detail: {
            NavigationStack(path: $widePath) {
                sectionContent(model.section)
                    .background(HibroTheme.background)
                    .navigationDestination(for: ShellRoute.self) {
                        routeDestination($0)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func navigationRow(_ section: AppSection) -> some View {
        Button {
            model.section = section
        } label: {
            HStack {
                Label(section.title, systemImage: section.symbol)
                Spacer()
                if section == .inbox {
                    let count = model.inboxItems.filter(\.requiresAttention).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(HibroTheme.orange, in: Capsule())
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            model.section == section
                ? HibroTheme.accent.opacity(0.09)
                : Color.clear
        )
    }

    private func compactTab<Content: View>(
        _ section: AppSection,
        path: Binding<NavigationPath>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .background(HibroTheme.background)
                .navigationDestination(for: ShellRoute.self) {
                    routeDestination($0)
                }
        }
        .tabItem {
            Label(section.title, systemImage: section.symbol)
        }
        .tag(section)
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            HibroMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("HIBRO").font(.headline)
                Text(model.currentUser?.displayName ?? "Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .inbox: InboxView()
        case .runs: RunsView()
        case .more: MoreView()
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: ShellRoute) -> some View {
        switch route {
        case .inbox(let id):
            InboxItemDetailView(itemID: id)
        case .conversation(let id):
            ConversationDetailView(conversationID: id)
        case .run(let id):
            RunDetailView(runID: id)
        }
    }

    private func show(_ route: ShellRoute) {
        if horizontalSizeClass == .compact {
            switch model.section {
            case .home:
                homePath = NavigationPath()
                homePath.append(route)
            case .inbox:
                inboxPath = NavigationPath()
                inboxPath.append(route)
            case .runs:
                runsPath = NavigationPath()
                runsPath.append(route)
            case .more:
                morePath = NavigationPath()
                morePath.append(route)
            }
        } else {
            widePath = NavigationPath()
            widePath.append(route)
        }
        preferredCompactColumn = .detail
    }
}
