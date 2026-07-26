import SwiftUI
import QuickLook
import UIKit

struct ArtifactsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        Group {
            if filteredArtifacts.isEmpty {
                EmptyStateView(
                    symbol: "doc.text",
                    title: "还没有产出",
                    message: "Agent 完成包含结果的运行后，产出会显示在这里。"
                )
            } else {
                List(filteredArtifacts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(HibroTheme.orange)
                                .frame(width: 40, height: 40)
                                .background(
                                    HibroTheme.orange.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 11)
                                )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(artifact.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeBytes), countStyle: .file)) · \(DateText.relative(artifact.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("产出")
        .searchable(text: $search, prompt: "搜索标题或内容")
    }

    private var filteredArtifacts: [CoreArtifact] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.artifacts }
        return model.artifacts.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content?.localizedCaseInsensitiveContains(query) == true
        }
    }
}

struct ArtifactDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var artifact: CoreArtifact
    @State private var contentData: Data?
    @State private var localFile: URL?
    @State private var previewFile: URL?
    @State private var isLoading = false

    init(artifact: CoreArtifact) {
        _artifact = State(initialValue: artifact)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(artifact.title)
                            .font(.title2.bold())
                        Text(metadataSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let localFile {
                        ShareLink(item: localFile) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await prepareFile(openPreview: false) }
                        } label: {
                            Label("准备分享", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isLoading)
                    }
                }
                Divider()
                if let content = textContent {
                    Text(content)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在从 Core 读取产出…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(spacing: 14) {
                        EmptyStateView(
                            symbol: "doc.viewfinder",
                            title: previewTitle,
                            message: previewMessage
                        )
                        Button {
                            Task { await prepareFile(openPreview: true) }
                        } label: {
                            Label("下载并预览", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("产出详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artifact.id) {
            await loadContent()
        }
        .quickLookPreview($previewFile)
    }

    private var metadataSummary: String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(artifact.sizeBytes),
            countStyle: .file
        )
        return [artifact.fileName, artifact.contentType, size]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " · ")
    }

    private var textContent: String? {
        if let content = artifact.content { return content }
        guard artifact.encoding != "base64",
              let contentData,
              artifact.previewKind == "markdown"
                || artifact.previewKind == "text"
                || artifact.previewKind == "code"
                || artifact.previewKind == "json"
                || artifact.contentType.hasPrefix("text/")
                || artifact.contentType.contains("json")
        else {
            return nil
        }
        return String(data: contentData, encoding: .utf8)
    }

    private var image: Image? {
        guard artifact.previewKind == "image",
              let contentData,
              let image = UIImage(data: contentData)
        else {
            return nil
        }
        return Image(uiImage: image)
    }

    private var previewTitle: String {
        artifact.transferStatus == "failed"
            ? "产出上传失败"
            : "使用系统预览打开"
    }

    private var previewMessage: String {
        if artifact.transferStatus == "failed" {
            return artifact.uploadError ?? "Core 暂时无法提供这份产出。"
        }
        return "PDF、音视频和其他文件类型会下载后交给系统安全预览。"
    }

    private func loadContent() async {
        guard artifact.transferStatus != "failed" else { return }
        isLoading = true
        defer { isLoading = false }
        if let result = await model.loadArtifact(id: artifact.id) {
            artifact = result.0
            contentData = result.1.data
        }
    }

    private func prepareFile(openPreview: Bool) async {
        isLoading = true
        defer { isLoading = false }
        if localFile == nil {
            localFile = await model.downloadArtifact(id: artifact.id)
        }
        if openPreview {
            previewFile = localFile
        }
    }
}
