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
                    message: "Agent 明确生成的文件、报告、图片和补丁会显示在这里；文本回复请在对话中查看。"
                )
            } else {
                List(filteredArtifacts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        ArtifactRow(artifact: artifact)
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

private struct ArtifactRow: View {
    let artifact: CoreArtifact

    var body: some View {
        HStack(spacing: 13) {
            ArtifactThumbnail(artifact: artifact, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if artifact.isImage {
                        Text("图片")
                    }
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(artifact.sizeBytes),
                            countStyle: .file
                        )
                    )
                    Text("·")
                    Text(DateText.relative(artifact.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct ArtifactThumbnail: View {
    @Environment(AppModel.self) private var model
    let artifact: CoreArtifact
    var size: CGFloat = 56
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: artifact.displaySymbol)
                    .font(.title3)
                    .foregroundStyle(
                        artifact.isImage ? HibroTheme.cyan : HibroTheme.orange
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        (artifact.isImage ? HibroTheme.cyan : HibroTheme.orange)
                            .opacity(0.1)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24)
                .stroke(HibroTheme.border)
        }
        .task(id: thumbnailTaskID) {
            guard artifact.isImage,
                  artifact.isContentAvailable,
                  artifact.sizeBytes <= 25 * 1_024 * 1_024,
                  let result = await model.loadArtifact(id: artifact.id)
            else {
                return
            }
            thumbnail = UIImage(data: result.1.data)
        }
    }

    private var thumbnailTaskID: String {
        "\(artifact.id):\(artifact.transferStatus ?? "legacy")"
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
                        .accessibilityLabel("图片预览")
                        .accessibilityIdentifier("artifact.imagePreview")
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
        if artifact.encoding != "base64", let content = artifact.content {
            return content
        }
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
        guard artifact.isImage,
              let contentData,
              let image = UIImage(data: contentData)
        else {
            return nil
        }
        return Image(uiImage: image)
    }

    private var previewTitle: String {
        if artifact.transferStatus == "failed" {
            return "产出上传失败"
        }
        if !artifact.isContentAvailable {
            return "图片仍在同步"
        }
        return artifact.isImage ? "图片暂时无法显示" : "使用系统预览打开"
    }

    private var previewMessage: String {
        if artifact.transferStatus == "failed" {
            return artifact.uploadError ?? "Core 暂时无法提供这份产出。"
        }
        if !artifact.isContentAvailable {
            return "Node 正在将文件上传到 Core，稍后刷新即可查看。"
        }
        return "PDF、音视频和其他文件类型会下载后交给系统安全预览。"
    }

    private func loadContent() async {
        guard artifact.transferStatus != "failed",
              artifact.isContentAvailable else {
            return
        }
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
