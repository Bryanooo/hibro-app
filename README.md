# Hibro App

Hibro App 是 Hibro Core 的原生 iPhone / iPad 客户端。项目使用 SwiftUI，
同一个 Target 同时支持 iPhone 和 iPad，不直接连接 Hibro Node。

## 产品结构

App 以人的工作流为中心，而不是把 Core Console 搬到移动端：

- **Home**：优先展示需要人的决定、正在推进的目标和最近交付
- **Inbox**：聚合审批、Agent 问题、失败任务和完成结果
- **Runs**：围绕目标查看执行流程、协作者、结果与产出
- **More**：Agent、Conversation、Artifact 和设置等资源入口

iPhone 使用四栏 Tab 导航，iPad 使用对应的 Sidebar + Detail 结构。Inbox
由 App 基于现有 Run Event 和 Conversation Activity 聚合，不要求 Core 增加新的
`/inbox` 或 `/home` 接口。

## 环境

- Xcode 26.6
- Swift 6.3
- iOS / iPadOS 17 或更高版本
- XcodeGen 2.46

## 生成与构建

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Hibro.xcodeproj \
  -scheme Hibro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

本机当前的全局 Developer Directory 指向 Command Line Tools，因此命令显式设置
`DEVELOPER_DIR`，无需修改系统全局配置。

## Personal Team 真机安装

App、单元测试和 UI 测试的 Bundle Identifier 分别为：

- `com.bryan.hibro`
- `com.bryan.hibro.tests`
- `com.bryan.hibro.uitests`

首次安装时：

1. 在 Xcode 的 `Settings > Accounts` 登录 Apple ID。
2. 用数据线连接并信任 iPhone 或 iPad。
3. 打开 `Hibro.xcodeproj`，选择 Hibro Target 的 `Signing & Capabilities`。
4. 保持 `Automatically manage signing` 开启，并在 `Team` 中选择对应的
   Personal Team。
5. 选择已连接的设备作为运行目标，点击 Run；对 iPhone 和 iPad 分别执行一次。

`DEVELOPMENT_TEAM` 有意不写入 `project.yml`，避免将个人 Team ID 固化在仓库中。
Xcode 选择的 Team 会保存在本机工程设置中；再次运行 XcodeGen 后如被清除，
重新选择 Personal Team 即可。

首次签名时，macOS 可能询问 `codesign` 是否可以访问 Apple Development 私钥。
输入 Mac 登录密码并选择“始终允许”，避免后续每次构建再次询问。

## 登录

App 使用 Hibro Core 已实现的 OAuth 2.0 Authorization Code + PKCE：

- Client ID：`hibro-ios`
- Redirect URI：`hibro://oauth/callback`
- Scope：`hibro.read hibro.run`
- Refresh Token：存储在 iOS Keychain

用于真机或非本机 Core 时应使用 HTTPS。Bark 通知会在后续作为可替换的
Notification Provider 接入 Core，本 App 已保留 `hibro://` 深度链接。

首次登录可以先“测试连接”。公网地址仅接受 HTTPS；Personal Team 在同一 Wi-Fi
联调时，可以输入 Core 显式启用的私有局域网 HTTP 地址。App 会请求本地网络权限，
并在设置页显示完整地址、连接安全状态及“更换 Hibro Core”入口。

当前产品默认预填正式 Core 地址 `https://hibro.online`，首次安装无需手动输入；
地址仍可编辑，以便迁移 Core 或进行局域网开发联调。

## Core API 兼容

当前控制面继续使用 Core v1 已有接口：

- `GET /v1/app/bootstrap`
- `GET/POST /v1/runs`
- `GET /v1/artifacts`
- `GET /v1/artifacts/:id`
- `GET /v1/artifacts/:id/content`
- `GET /v1/artifacts/:id/download`
- `GET /v1/conversations/:id`
- `POST /v1/conversations/:id/approval/:activityId`
- `GET /v1/runs/:id/events`
- `POST /v1/runs/:id/approval/:externalId`
- `GET /v1/events`

App 最多并发读取最近 20 个 Conversation Detail，用于恢复待处理 Activity；
同时读取最多 20 个活跃 Run 的事件，用于恢复直接 Run 审批。单个详情读取失败
不会阻断 Home、Runs 或其他首屏数据。登录后使用全局 SSE 驱动增量刷新，App
进入后台时停止连接，回到前台后自动恢复并同步。

OAuth 元数据中的 Issuer、授权地址和 Token 地址必须与用户选择的 Core 同源，
防止错误配置把登录或 Token 发送到其他主机。公网 Core 仍必须使用系统信任的 HTTPS。
