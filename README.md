# 墨读

墨读是一款 macOS 原生 Markdown 阅读与编辑应用，目标是提供轻量、顺滑、接近文档阅读器体验的 Markdown 工作台。

当前版本：`1.0.10`

## 功能

- Markdown 阅读：GitHub 风格渲染、目录侧栏、阅读字号设置。
- 直接编辑：基于 Vditor IR 的所见即所得 Markdown 编辑体验。
- 源码编辑：可关闭实时预览，回到传统 Markdown 源文本编辑。
- 文件管理：文件夹浏览、最近打开、Finder 打开 Markdown 文件。
- 编辑工具栏：标题、加粗、斜体、链接、图片、列表、引用、代码块、表格等常用操作。
- 原生 macOS 体验：SwiftUI 界面、文件类型注册、系统主题跟随。

## 系统要求

- macOS 14.0 或更高版本
- Swift 6 工具链

## 构建

```bash
git clone https://github.com/xxia-king/modu-public.git
cd modu-public
swift build
```

Release 构建：

```bash
swift build -c release
```

运行开发版本：

```bash
swift run
```

## 安装到 Applications

仓库提供了一个简单的本地启动脚本：

```bash
./run.sh
```

如果 `/Applications/墨读.app` 不存在，脚本会创建 app bundle、复制可执行文件和资源，并进行本地 ad-hoc 签名。

## 项目结构

```text
.
├── Package.swift
├── run.sh
├── generate_icon.swift
├── AppIcon.icns
├── icon.png
└── Sources/MarkdownReader
    ├── App.swift
    ├── Models
    ├── Views
    ├── Extensions
    └── Resources
        ├── vditor
        └── vditor-editor
```

## 技术栈

- SwiftUI
- Swift Package Manager
- MarkdownUI
- WKWebView
- Vditor IR

## 说明

本仓库包含应用源码和必要的前端编辑器静态资源。构建产物和本地私有工作区文件不纳入版本控制。

## 参与贡献

欢迎通过 issue 或 pull request 提交问题反馈、功能建议和代码改进。贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 作者与联系

金莉珊，浙江嘉瑞成律师事务所执业律师，坐标浙江温州。主要关注民商事争议解决，同时持续探索 AI 技术在法律工作中的应用。

- 个人主页：[https://jinlishan.com/](https://jinlishan.com/)
- 微信号：`jinlishan_`（添加请备注来自 GitHub）
- 公众号：日进斗金大壮
- 视频号：金莉珊律师

<p>
  <img src="assets/wechat-qr.jpg" alt="微信二维码" width="160">
  <img src="assets/qr-gongzhonghao.jpg" alt="公众号二维码" width="160">
  <img src="assets/qr-video.jpg" alt="视频号二维码" width="160">
</p>


## 许可证

本项目采用 [Apache License 2.0](./LICENSE) 开源。

第三方组件许可见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。
