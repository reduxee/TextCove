# TextCove

TextCove 是一款使用 SwiftUI 编写的 macOS 原生多标签文件查看与编辑器。界面由原生标题栏工具栏、自定义 Tab 栏和 AppKit 文本编辑器组成，支持 Markdown 预览、34 种语言的 tree-sitter 语法高亮、Vue 单文件组件分区高亮、任意编码文本编辑、本地文件保存与代码格式化。

- 部署目标：macOS 14.0+
- 验证环境：Xcode 27.1 / Swift 6.4 编译器（Swift 5 语言模式）/ Apple Silicon
- 工程格式：XcodeGen 生成，`TextCove.xcodeproj` 可直接打开

## 功能

- 自定义白底 App 图标：深色文档轮廓 + 两条文本线 + 蓝色 Cove 曲线。
- 原生工具栏：打开文件、保存、格式化；1.2 版新增编辑器行号、预览代码块行号与任意文本打开。
- 1.2.2 修复了行号导致编辑器正文不可见的问题：行号改为 SwiftUI 外层的独立侧栏，不再向 NSScrollView 内注入任何行号视图。
- 1.5.2 超大文件可用性：长行按窗口宽度自动折行（中文按 2 列宽计算，优先在空格处断开），不再被窗口右缘截断；支持拖选多行（强调色高亮），⌘C 或右键「复制」复制完整原始行；索引期间在视图顶部居中显示进度浮层（百分比 + 进度条）。
- 1.5.1 超大文件进度：说明栏显示确定进度条（「正在建立行索引 42%」），索引完成后切换为常规提示；进度通过 `onIndexProgress` 每 2% 回调一次。
- 1.5.0 超大文件：>64 MB 的文件不再整份读入内存，改用 mmap 只读分页查看器——1.12 GB / 521 万行的 SQL dump 首帧约 12 ms，常驻内存约 100 MB；支持行号、SQL 关键字着色、滚轮/翻页/拖动定位与复制行，不提供编辑与全文搜索。
- 1.4.1 性能：修复打开 / 关闭大文件（如 8.7 MB、20 万行）时的秒级卡顿。根因是拿 `NSTextView.string` 的桥接字符串做整串比较，一次约 650 ms；改为版本号 / token / 长度等 O(1) 判据后，打开从约 2.6 s 降到约 0.5 s、关闭约 1 ms。超长行文件（压缩产物）自动改为只读折行预览，行号扫描移到后台。
- 1.4.0 界面调整：去掉 Tab 栏下方的分隔线，正文收进 10pt 连续曲率的圆角卡片，Markdown 的编辑 / 预览切换改为右下角毛玻璃悬浮图标。
- 1.4.1 性能修复：窗口打开、关闭、输入都不再对整份文档做字符串比较；行号扫描改为后台 + 防抖；超长行（>5 万字符）自动只读折行预览。
- 1.3.1 修复：非 Markdown 文件打开时，行号侧栏会把上方 Tab 栏刷成背景色导致标签“消失”。侧栏不再填充 `dirtyRect`，背景改由外层容器提供。
- 1.3 版扩展语言与文本覆盖：Vue 单文件组件高亮、34 种 tree-sitter 语言的类型识别与图标、XML/plist/diff/nginx/GraphQL/.gitignore/.env 内置正则高亮、shebang 与 modeline 语言检测、非 UTF-8（GBK / Windows-1252 / ISO-8859-1 / UTF-16 / UTF-32）文件可打开并按原编码保存。
- 多 Tab：独立关闭、自定义滚动 Tab 栏、未保存星号标记。
- 文件打开：`NSOpenPanel`、拖拽到窗口，或从 Finder 直接打开；同一绝对路径自动复用已有 Tab。未知扩展名按普通文本编辑，只有含 NUL 的真正二进制文件会被拒绝。
- 文件类型：markdown、Vue、JavaScript/JSX、TypeScript/TSX、HTML、CSS、Java、C/C++/Objective-C、C#、Swift、Python、Ruby、Go、Kotlin、Rust、PHP、Lua、Shell、SQL、Scala、Dart、Elixir、Haskell、OCaml、Zig、YAML、TOML、JSON、Dockerfile、XML、plist、diff、nginx、GraphQL、.gitignore、.env，以及其他任意文本。
- 系统集成：`CFBundleDocumentTypes` 覆盖上述扩展名与 `public.text`/`public.source-code`/`public.xml` 等通用类型，可设为 Finder 默认应用。
- Markdown：编辑 / 预览互斥切换，入口是右下角的毛玻璃悬浮图标按钮（铅笔 / 眼睛）；WKWebView + 内置深浅 CSS；本地相对图片；预览内代码块显示行号。
- 代码编辑器：NSTextView、等宽字体、tree-sitter 高亮、跟随系统浅色 / 深色主题；除 Markdown 编辑器外均显示行号。
- 保存：原子写入、保存前二次确认、关闭未保存 Tab 时提供保存 / 丢弃 / 取消。
- 格式化：JSON 格式化与压缩（语法错误显示行、列和 ^ 位置）；JS/HTML/CSS 使用 js-beautify；其他类型禁用格式化按钮。
- 错误处理：读取失败、二进制文件、Markdown 渲染失败均有 Tab 内提示或弹窗；非 UTF-8 文件在编辑器顶部显示所用编码提示。

## 本机打包与安装

已经生成可直接使用的产物：

- `dist/TextCove.app`：1.5.2 Release 版应用，已进行本机 ad-hoc 签名，通用二进制（arm64 + x86_64）。
- `dist/TextCove-1.5.2-macOS.zip`：约 19 MB。
- `dist/TextCove-1.5.2-macOS.dmg`：约 24 MB 的安装镜像。

在自己电脑上使用只需：

1. 双击 DMG，或解压 zip。
2. 将 `TextCove.app` 拖到“应用程序”文件夹。
3. 双击打开。由于没有 Apple Developer ID 证书，这是用于本机自用的 ad-hoc 签名版本，不需要也不应提交 App Store。

之前安装过旧版的话，先退出旧版，再用 1.5.2 覆盖 `/Applications/TextCove.app`。1.3.x 新增了 Vue、更多语言与文档类型声明，并修复了非 Markdown 文件打开时 Tab 栏不显示的问题，需要重新安装、并让 LaunchServices 重新登记后才会生效：

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -f /Applications/TextCove.app
```

如果 macOS 首次打开时提示无法验证开发者，可右键 App → 打开，或前往“系统设置 → 隐私与安全性 → 仍要打开”。若 App 被加上了下载隔离属性，也可执行：

```bash
xattr -dr com.apple.quarantine /Applications/TextCove.app
```

自行用 Xcode 打包时：

1. 在 Signing & Capabilities 选择 “Sign to Run Locally”（不要求开发者账号）。
2. Product → Scheme → Edit Scheme，将 Run 的 Build Configuration 改为 Release（或直接 Product → Build 后从 Products 目录取 App）。
3. 如果产品导航器里看不到 Products，使用 Product → Show Build Folder in Finder，在 `Build/Products/Release/` 下找到 `TextCove.app`。
4. 将 `.app` 拖入“应用程序”。

如果要发给其他 Mac 使用，建议使用 Apple Developer ID 证书签名并公证；仅 ad-hoc 签名的 App 在别的机器上可能被 Gatekeeper 拦截。需要通用二进制时，将 Release 构建的 `ARCHS` 设为 `arm64 x86_64`，并关闭 `ONLY_ACTIVE_ARCH`。

## 设为默认打开

macOS 不会在安装新应用后自动替换已有的默认应用，需要手动选择一次。已安装 1.3.0 并至少打开过一次 TextCove 后：

1. 在 Finder 里随便选中一个 `.md` 文件，按 `⌘I` 打开“显示简介”。
2. 在“打开方式”下拉框选择 TextCove；若列表里没有，选“其他…”后手动选择 `/Applications/TextCove.app`。
3. 点击“全部更改…”（Change All…），确认后 `.md` 文件就会默认用 TextCove 打开。
4. 对 `.js`、`.ts`、`.html`、`.css`、`.java`、`.c`、`.swift`、`.yml`、`.json`、`.plist` 等类型分别重复一次，因为 macOS 是按内容类型分别记录默认应用的。通用文本类型也可以在“其他文本”中设置。`.ts` 在 macOS 自带类型库中与 MPEG 传输流存在扩展名冲突，若找不到它，请用“其他…”手动选择 TextCove。

如果“打开方式”里始终没有 TextCove，先启动一次 App，然后刷新 LaunchServices 注册：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/TextCove.app
```

必要时重启 Finder。之后即可直接双击文件，由 TextCove 新建或切换到对应 Tab。应用使用 `LSHandlerRank = Alternate`，表示它可以作为编辑器候选，但不会在用户未确认时强行抢占系统默认应用。

## 直接运行

1. 用 Xcode 打开 `TextCove.xcodeproj`。
2. 等待 Swift Package 依赖解析完成。首次解析需要访问 GitHub。
3. 在 Target `TextCove` 的 Signing & Capabilities 中选择自己的 Team，或使用 “Sign to Run Locally”。
4. 选择 My Mac，运行。

工程使用 `Config/Info.plist` 显式声明文档类型，并有意关闭了 App Sandbox，以便本地文件打开、保存和 WKWebView 预览直接工作。若要上架 Mac App Store，需要补充安全作用域书签、沙盒权限和签名配置，详见“潜在坑点”。

命令行构建：

```bash
xcodebuild \
  -project TextCove.xcodeproj \
  -scheme TextCove \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 从零创建 Xcode 工程

已有工程可直接跳过本节。复现步骤：

1. Xcode → File → New → Project → macOS → App。
   - Product Name：`TextCove`
   - Interface：SwiftUI
   - Language：Swift
2. Deployment Target 设为 macOS 14.0。
3. File → Add Package Dependencies，添加：
   - `https://github.com/CodeEditApp/CodeEditLanguages.git`，Exact Version `0.1.21`
   - `https://github.com/ChimeHQ/SwiftTreeSitter.git`，Exact Version `0.9.0`
4. 在 Target → General → Frameworks, Libraries, and Embedded Content 中加入两个产品：
   - `CodeEditLanguages`
   - `SwiftTreeSitter`
5. 创建 `TextCove/` 下的目录结构，加入源码。
6. 把 `TextCove/Resources/` 中的 JavaScript 文件加入 Target 的 Copy Bundle Resources：
   - `markdown-it.min.js`
   - `beautify-js.js`
   - `beautify-html.js`
   - `beautify-css.js`
7. 新建 `Config/Info.plist` 并在 Build Settings 设置：
   - `INFOPLIST_FILE = Config/Info.plist`
   - `GENERATE_INFOPLIST_FILE = NO`
   - `MACOSX_DEPLOYMENT_TARGET = 14.0`
   - `SWIFT_VERSION = 5.0`
   - `ENABLE_APP_SANDBOX = NO`
   - `PRODUCT_BUNDLE_IDENTIFIER = com.textcove.TextCove`
   - `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
   - `MARKETING_VERSION = 1.5.2`
8. 在 `Info.plist` 中加入 `CFBundleDocumentTypes`，声明常用代码、plist 及通用文本的 UTI 与扩展名，并加入 `AppDelegate` 的 `application(_:open:)` 处理。
9. 运行工程。最小窗口限制由 `ContentView` 的 `frame(minWidth:minHeight:)` 配合 `.windowResizability(.contentMinSize)` 实现。

本工程的 `project.yml` 是 XcodeGen 配置，修改源码目录或依赖后可用以下命令重新生成 `.xcodeproj`：

```bash
xcodegen generate
```

## SPM 依赖清单

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| CodeEditApp/CodeEditLanguages | `0.1.21` | 打包 tree-sitter 各语言 grammar 与 highlight query，提供 `CodeLanguage` |
| ChimeHQ/SwiftTreeSitter | `0.9.0` | Swift tree-sitter 运行时/查询 API |
| tree-sitter/tree-sitter | `0.23.2`（间接） | SwiftTreeSitter 0.9.0 依赖的 C 运行时 |

关键版本约束：

- `CodeEditLanguages 0.1.21` 内部使用 `SwiftTreeSitter 0.9.0` 和 tree-sitter 0.23.x 编译的二进制 grammar。项目将 SwiftTreeSitter 固定为 `0.9.0`，避免解析到新版运行时后出现 grammar ABI 不兼容。
- 工程附带的 `Package.resolved` 锁定了各包的 revision。
- `CodeLanguagesContainer.xcframework` 同时包含 arm64 和 x86_64 slice。

本地打包的 JavaScript 依赖（非 SPM，通过 JavaScriptCore 离线执行）：

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| markdown-it | `14.1.0` | Markdown → HTML，CommonMark、表格、删除线、自动链接、任务列表 |
| js-beautify | `2.0.3` | JavaScript / HTML / CSS 格式化 |

许可证见 `TextCove/Resources/THIRD_PARTY_NOTICES.txt`。

## 项目目录

```text
TextCove/
├── .gitignore
├── README.md
├── project.yml
├── TextCove.xcodeproj/
│   ├── project.pbxproj
│   ├── xcshareddata/xcschemes/TextCove.xcscheme
│   └── project.xcworkspace/
│       ├── contents.xcworkspacedata
│       └── xcshareddata/swiftpm/Package.resolved
├── dist/
│   ├── TextCove.app
│   ├── TextCove-1.5.2-macOS.zip
│   └── TextCove-1.5.2-macOS.dmg
├── Config/
│   └── Info.plist
└── TextCove/
    ├── Assets.xcassets/
    │   └── AppIcon.appiconset/
    ├── App/
    │   ├── TextCoveApp.swift
    │   ├── TextCoveCommands.swift
    │   └── AppDelegate.swift
    ├── Models/
    │   ├── FileKind.swift
    │   ├── EditorDocument.swift
    │   └── WorkspaceModel.swift
    ├── Editor/
    │   ├── EditorTheme.swift
    │   ├── SyntaxHighlighter.swift
    │   ├── VueHighlighter.swift
    │   ├── RegexHighlighter.swift
    │   ├── CodeTextView.swift
    │   ├── EditorViewport.swift
    │   ├── LineNumberSidebar.swift
    │   ├── CodeEditorView.swift
    │   └── CodeEditorPane.swift
    ├── LargeFile/
    │   ├── MappedTextFile.swift
    │   ├── HugeFileView.swift
    │   └── SQLLineTokenizer.swift
    ├── Markdown/
    │   ├── MarkdownHTMLRenderer.swift
    │   ├── MarkdownPreviewStyles.swift
    │   ├── MarkdownPreviewView.swift
    │   └── LocalAssetSchemeHandler.swift
    ├── Formatting/
    │   ├── CodeFormatter.swift
    │   └── JSONFormatter.swift
    ├── Utilities/
    │   └── FileDropLoader.swift
    ├── Views/
    │   ├── ContentView.swift
    │   ├── DocumentTabBar.swift
    │   ├── DocumentContainerView.swift
    │   ├── DocumentStatusView.swift
    │   └── EmptyWorkspaceView.swift
    └── Resources/
        ├── markdown-it.min.js
        ├── beautify-js.js
        ├── beautify-html.js
        ├── beautify-css.js
        └── THIRD_PARTY_NOTICES.txt
```

## 关键实现

### Finder 打开与默认应用

- `Config/Info.plist` 的 `CFBundleDocumentTypes` 声明 Markdown、JavaScript、TypeScript、HTML、CSS、Java、C、Swift、YAML、JSON、plist，以及通用 `public.text`/`public.source-code` 文档类型，角色为 `Editor`，等级为 `Alternate`。这使 TextCove 出现在 Finder 的“打开方式”中，同时不强制夺取用户现有的默认应用。
- `AppDelegate` 实现 `application(_:open:)`，接收 LaunchServices 发来的文件 URL，直接复用现有 `WorkspaceModel` 打开 Tab；冷启动和运行中打开都走同一路径。
- `TextCoveApp` 通过 `@NSApplicationDelegateAdaptor` 持有唯一的 `WorkspaceModel`，因此启动时文件事件早于窗口出现也不会丢失。
- 已验证通过 LaunchServices 打开 `readme.md` 时，应用会自动创建对应 Tab。

### 1. 工具栏与 Tab

- `WorkspaceModel` 持有 `[EditorDocument]` 和 `selectedID`。打开文件时使用标准化绝对路径 `standardizedFileURL.path` 查重，命中后只切换 `selectedID`，不会重复读取或新建 Tab。
- `ContentView` 使用原生 `.toolbar` 放置打开、保存和格式化控件；`DocumentTabBar` 是自定义横向 Tab 栏，每个 Tab 独立观察自己的 `EditorDocument`，因此标题星号能随编辑实时变化。
- `WorkspaceModel` 订阅每个文档的 `objectWillChange`，只在 `canSave` / `canFormat` 这类工具栏状态发生变化时重新发布；避免每次击键都重绘整个界面，同时保证保存按钮的可用状态及时更新。

### 2. 打开、读取、保存

- 打开面板允许选择任意文件；未知扩展名也会按普通文本进入编辑器，只有含 NUL 且不带 UTF-16/32 BOM 的内容会被判定为二进制并拒绝。
- 文件内容在后台 `Task.detached` 中读取，主线程负责更新状态。解码顺序为：UTF-16 / UTF-32（按 BOM 识别）→ UTF-8（自动剥离 UTF-8 BOM）→ GBK（要求解出汉字才采纳）→ Windows-1252 → ISO-8859-1。命中的编码记录在 `EditorDocument.sourceEncoding`，保存时沿用同一编码并还原文件头部的 BOM，因此老编码的文件不会被悄悄改写成 UTF-8；非 UTF-8 时编辑器顶部显示一条编码提示。
- 保存使用 `Data.write(options: .atomic)` 原子写入原路径。`text != savedText` 决定脏状态，保存成功后将 `savedText` 更新为当前文本。
- 工具栏保存和 `⌘S` 都先弹出覆盖确认；关闭脏 Tab 使用三按钮对话框：保存 / 丢弃修改 / 取消。关闭操作优先选择相邻 Tab。

### 3. tree-sitter 高亮

- `SyntaxHighlighter` 是唯一入口，按 `FileKind.highlighting` 分派到三种引擎：`treeSitter`（CodeEditLanguages 的 34 种语法）、`vueSFC`（分区投影）、`regex`（内置正则规则）。三者都产出同一种 `HighlightToken(range, captureName)`，由 `EditorTheme.style(forCapture:)` 统一上色，因此新增语言不需要改动编辑器代码。
- tree-sitter 语言检测调用 `CodeLanguage.detectLanguageFrom(url:prefixBuffer:suffixBuffer:)`：先看扩展名 / 文件名（含 `Dockerfile`），再退到 shebang（`#!/usr/bin/env python3`）和 vim/emacs modeline，因此无扩展名脚本也能高亮。`Agda`、`Julia`、`Perl`、`Verilog` 虽有 grammar，但 `TreeSitterModel.query(for:)` 直接返回 `nil`，只能当纯文本。
- `EditorTheme` 覆盖 tree-sitter 官方 highlight query 里的全部 capture 家族：`comment`、`keyword`、`string`、`number/boolean/constant/float`、`function/method`、`type/constructor/label/interface/module`、`property/field`、`attribute`、`tag`、`variable/identifier/parameter`、`operator/punctuation/delimiter`、`conditional/repeat/include/storageclass/exception/preproc`、`character/symbol/escape/embedded`、Markdown 的 `text.title/strong/emphasis/literal/uri/reference`，以及 Objective-C 的 `@protocol/@selector/@try/@end/...` 专有 capture 和 diff 的 `diff.inserted/deleted/header/chunk/command`。`fold`、`indent.*`、`local.*`、`injection.content` 这类只服务于缩进和注入的 capture 被有意忽略。
- 高亮在专用串行队列中执行，每次编辑后防抖约 120ms；超出 1,000,000 个 UTF-16 code unit 的文件退化为纯文本样式，避免卡顿。
- SwiftTreeSitter 的 `Parser.parse(String)` 按 UTF-16 解析，因此 `node.range` 可以直接作为 `NSTextStorage` 的 `NSRange` 使用，不需要手工做 UTF-8 到 UTF-16 的偏移换算。
- 应用属性时保存选区、关闭 undo registration、批量编辑 text storage，再恢复选区；不会污染文本撤销栈，也不会触发 SwiftUI 的文本回写循环。
- 非 Markdown 编辑器采用 SwiftUI 外层 `HStack`：左侧是独立的 `LineNumberSidebar`，右侧是原来的纯 `NSScrollView` 编辑器。`EditorViewport` 在两者之间共享文本视图引用；行号侧栏按 layout manager 的可见行片段定位并监听滚动。该方案不会向编辑器滚动视图注入子视图，因此不会影响正文渲染。Markdown 编辑模式不显示行号。
- Markdown 预览的 fenced/indented 代码块通过自定义渲染器生成行号列，行号与代码使用相同行高，横向滚动和浅深色主题均适用。
- `EditorTheme` 提供浅色 / 深色两套语义色，并与 Markdown 预览的 GitHub 风格配色保持一致。

### 3.1 Vue 单文件组件：分区投影高亮

- CodeEditLanguages 没有 vue 语法；npm 上唯一的 `tree-sitter-vue@0.2.1` 自 2022 年停更、不带 highlight query，因此改为复用已有语法：`<template>` 用 HTML 语法，`<script>` 按 `lang` 属性用 JavaScript / TypeScript / TSX / JSX，`<style>` 用 CSS。
- 关键技巧是投影（projection）：复制一份原文，把非目标区域的字符逐位替换成空格（保留 `\n`、`\r`），得到一份 **UTF-16 长度与原文完全相同** 的字符串再交给 `Parser.parse`。由于 SwiftTreeSitter 以 UTF-16 为单位返回 range，投影串上的 capture 可以直接当作原文件的 `NSRange` 使用，不需要偏移换算，emoji 等多码元字符也不会错位。
- 每个语法跑完后按区间过滤：HTML 遍丢弃与 script/style 正文重叠的 token，内嵌遍只保留完全落在该正文内的 token，避免语法边界猜测造成的串色。
- 区块扫描在 UTF-16 数组上手工完成（`<script` / `<style` 开头 + 标签名结束符判定 + 对应的闭合标签），因此 `<template>` 内嵌套 `<template>`、`<script setup>`、`lang="ts"` 都能正确处理。

### 3.2 内置正则高亮

- 用于没有 tree-sitter 语法但常见的文本：XML/SVG、plist、diff/patch、nginx.conf、GraphQL、`.gitignore`、`.env`。规则表在 `RegexHighlighter` 中按语言声明，ICU 正则编译一次后缓存。
- 冲突处理采用“起点优先 + 声明顺序优先 + 先占位者胜”：所有匹配按起点排序，同起点时规则表靠前的胜出，之后与已选区间重叠的匹配全部丢弃。这样注释与 CDATA 能完整覆盖内部的尖括号，`<key>` 这类高优先级规则也能压过通用标签规则。
- plist 复用 XML 规则，并额外加了一条固定宽度后视 `(?<=<key>)[\s\S]*?(?=</key>)`，把字典键显示成属性色。

### 4. Markdown 预览

- `MarkdownHTMLRenderer` 在 JavaScriptCore 中运行本地 `markdown-it.min.js`，启用表格、删除线、自动链接、inline HTML，并通过一个轻量 core rule 支持 GFM 任务列表。
- `WKWebView.loadHTMLString(_:baseURL:)` 的 `baseURL` 明确设置为 Markdown 文件所在目录。
- 由于签名 App 中的 WKWebView 对 `file://` 子资源的访问并不可靠，Markdown 图片会被改写到自定义 `textcove-asset://local/...` scheme，由 `LocalAssetSchemeHandler` 从 Markdown 所在目录解析并仅加载图片类型。这样既保留了 baseURL 的语义，又能稳定显示相对路径图片，包括 `../` 路径。
- HTML 中内置两套 CSS 变量，通过 `@media (prefers-color-scheme: dark)` 跟随系统。WKWebView 的 appearance 也会随 SwiftUI 的 `colorScheme` 更新。
- WebView 禁用内容 JavaScript，并用 CSP 禁止脚本、iframe、表单和网络连接；只允许图片与媒体资源。外链由 `WKNavigationDelegate` 转交给默认浏览器，不在预览内导航。
- Markdown 的编辑 / 预览按钮使用 `MarkdownMode` 状态和 `if/else` 互斥渲染。编辑内容实时回写 `EditorDocument.text`，切换预览时直接使用该最新文本。
- 1.4 起 `DocumentContainerView` 把正文统一收进 `clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))` 的卡片：卡片背景用 `textBackgroundColor`，外层窗口用 `windowBackgroundColor`，四周留 8pt 边距形成层次。Markdown 切换按钮是 `ZStack(alignment: .bottomTrailing)` 上的悬浮胶囊，用 `.regularMaterial` 做毛玻璃、`shadow` 提亮边缘，选中项用 `Color.primary.opacity(0.10)` 底色区分。Tab 栏下方不再放 `Divider`，分隔交给卡片自身的留白与描边。

### 5. 格式化

- JSON 使用自实现的 lexer + 递归下降校验器：
  - 保留键顺序，不依赖 `JSONSerialization` 的字典重排。
  - 格式化 / 压缩都只重写空白，不改变字符串与数字字面量。
  - 语法错误会给出 1-based 行号、列号、错误原因、相关行和 `^` 指示。
  - 支持 CRLF、Unicode、嵌套、转义和控制字符校验。
- JS/HTML/CSS 调用本地 js-beautify 2.0.3。JavaScriptCore 默认没有 `self/window/global`，因此初始化时注入了浏览器式全局垫片，并禁用了 JS 的联网能力。
- 非法 JSON 的格式化错误通过弹窗显示；YML、Java 和 Markdown 的格式化入口处于禁用状态。

### 6. 错误与空状态

- 读取失败、二进制或非 UTF-8 文件使用 Tab 内的状态页展示，并提供重试按钮。
- 拖入文件夹会拒绝并显示提示。
- Markdown 渲染器初始化或执行失败时，WKWebView 内显示错误页。
- 所有对话框与工具栏操作都通过 Workspace 的集中状态驱动。

### 7. 超大文件只读查看器（1.5.0）

- 触发条件：文件 ≥ 64 MB。此时 `EditorDocument` 完全不读文件内容，只记录大小并直接进入 `.loaded`；`canSave` / `canFormat` 为 false。
- `MappedTextFile` 用 `mmap(MAP_PRIVATE)` 只读映射文件，绘制时按字节范围取行，不建 `String`、不建 `NSTextStorage`。1.12 GB 文件的 `mmap` + 首帧约 12 ms。
- 行定位用「每 1024 行一个锚点」的稀疏索引：全文件约 5,100 条、几十 KB；跳转时锚点二分 + 块内扫描，1/3 处定位耗时 <1 ms。
- 索引在后台用 `pread` 读 1 MB 块扫描换行，**不用 mmap 扫全文件**——否则 1.12 GB 的页缓存会全部计入进程常驻内存（实测 RSS 会涨到 2.3 GB）。扫描结束后再 `madvise(MADV_DONTNEED)` 把零星触碰的映射页还给系统，常驻稳定在约 100 MB。
- 索引进度通过 `onIndexProgress`（每 2% 一次，主线程）回传给 SwiftUI，在说明栏显示 `ProgressView` 与百分比；索引完成后自动切换成常规说明。
- `HugeFileView` 是自绘 `NSView`：只画可见的几十行，行号在左侧 gutter，垂直滚动由 `NSScroller` 手动映射到字节偏移，不创建「500 万行 × 行高」的巨型 documentView。
- 折行在显示层做：按 `列数 = 文本宽度 / 等宽字符宽` 切段，中文等全角字符按 2 列计、优先在空格处断开；滚动按「显示行」推进，行号只画在逻辑行首行。切段与着色结果按行缓存，滚动 40 行约 1.4 ms。
- 选择按「逻辑行」实现：单击选中、拖动扩展（拖到边缘自动滚动），高亮用强调色 22% 透明度；`copy(_:)` + 右键菜单 + `NSUserInterfaceValidations` 让 ⌘C 走通菜单，复制的是完整原始行（不受折行影响）。
- 索引进度既有说明栏的 `ProgressView`，也在视图顶部居中画一个浮层（百分比 + 进度条），索引完成即消失。
- 着色只在可见行上做：`SQLLineTokenizer` 把单行切成关键字 / 字符串 / 数字 / 注释 / 反引号标识符，按主题上色，单帧 40 行约 2.7 ms。
- 单行超过 4,000 字符时截断显示并标注，避免个别超长 INSERT 拖慢绘制。

## 潜在坑点与设计边界

1. **依赖 ABI**：不要把 SwiftTreeSitter 升级到 0.10+，除非同步验证 CodeEditLanguages 的二进制 grammar。固定为 0.9.0 / tree-sitter 0.23.x 更稳妥。
2. **tree-sitter 区间单位**：本项目通过 `Parser.parse(String)` 使用 UTF-16 输入；如果改用 UTF-8 read block，`node.range` 的单位会变化，需要重新做偏移换算。
3. **WKWebView 本地文件**：`baseURL` 不保证在签名 App 中允许本地子资源访问。因此图片使用受限 scheme 代理。不要删除这一层，除非自行验证目标签名和沙盒环境。
4. **沙盒**：工程关闭 App Sandbox。若开启沙盒，需要在打开时保存 security-scoped bookmark，并在读取、保存、图片代理和重新打开时持有安全作用域；否则文件读写会被拒绝。
5. **内容安全**：预览允许 Markdown 原始 HTML，但内容 JS 被禁用，CSP 也禁止脚本与网络连接。若开启页面 JS，请先引入 HTML sanitizer。
6. **编码**：UTF-8 之外的文件按 GBK → Windows-1252 → ISO-8859-1 顺序回退，并沿用原编码写回，因此不会把老编码文件悄悄转成 UTF-8。GBK 排在 Windows-1252 之前并要求解出汉字，属于启发式判断：单个 Latin-1 文件若恰好能构成合法 GBK 且含汉字，仍可能被识别成 GBK，需要时请自行转存 UTF-8。新 SDK 已移除 `String.Encoding` 的中文常量，只能通过 `CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))` 取 GBK；GB18030 在本机返回 `nil`，因此没有列入回退链。UTF-8 BOM 会在读取时剥离、保存时还原，UTF-16/32 依赖 BOM 识别。
7. **大文件**：高亮超过 1M UTF-16 code unit 会关闭语法高亮；Markdown 渲染和整份文档比较仍可能对超大文件产生开销。未实现 tree-sitter 增量解析。
8. **窗口退出**：按需求实现了关闭 Tab 的未保存确认，但没有拦截整个窗口关闭 / `⌘Q`。若用于生产，建议补充窗口级或应用级脏文档确认。
9. **视图状态**：切换 Tab 或 Markdown 模式会新建编辑器视图，文本内容会保留，但该视图内的光标、选区和 undo 历史不会跨切换保留。
10. **外部修改**：应用不会监听磁盘文件的外部变更；保存时会覆盖磁盘内容。可按产品需要加入 mtime 检测或文件协调。
11. **架构**：CodeEditLanguages 的 xcframework 支持 arm64 与 x86_64；`Package.resolved` 固定了这些远程依赖的精确 revision。
12. **网络**：第一次打开工程必须能访问 GitHub 以拉取 SPM 包。当前验证环境的 `git clone` 被网络策略阻断，因此使用了同版本本地归档完成编译验证，最终工程配置仍为标准远程 SPM 引用。
13. **默认应用**：如果系统仍使用旧版本或找不到 TextCove，先退出旧进程并替换 `/Applications/TextCove.app`，再刷新 LaunchServices；然后针对每种扩展名执行一次“全部更改”。
14. **Vue 区块扫描的标签长度**：`<script` 是 7 个 UTF-16 单位，`<style` 只有 6 个。早期版本硬编码 `index + 7`，导致 `<style scoped>` 整块被跳过、style 正文一个 token 都没有。区块关键字必须由 `blockKeywords` 表提供，不能再写死长度。
15. **`UInt16(ascii:)` 不存在**：Swift 只有 `UInt8(ascii:)`。`UniChar` 比较要使用显式数值常量（`gtUnit = 62`、`spaceUnit = 32` 等），否则编译期直接报“no exact matches in call to initializer”。
16. **投影必须逐位等长**：隐藏区只能替换成空格并保留换行。改成删除字符或替换成变长内容都会让 capture 的 UTF-16 偏移指到错误位置，症状是“高亮整体错位一段”。
17. **正则高亮的优先级语义与 tree-sitter 相反**：tree-sitter 路径依赖“后写覆盖”，让更内层、更具体的 capture 胜出；正则路径是“先占位者胜”，因此规则声明顺序本身就是优先级，注释 / CDATA / `<key>` 这类规则必须写在通用标签规则之前。
18. **SF Symbols 可用性**：`rust`、`chevron.left.forwardslash.php` 在本机解析为 `nil`（图标位置空白但不崩溃），已改用 `r.square.fill` 与 `elephant`。新增语言图标时建议先用 `NSImage(systemSymbolName:accessibilityDescription:)` 批量校验一遍。
19. **超大文件别用 mmap 扫全量索引**：映射页会全部计入进程 RSS（1.12 GB 文件实测 2.3 GB）。索引用 `pread` 逐块读，收尾 `madvise(MADV_DONTNEED)`；绘制仍用 mmap 才能零拷贝取行。
20. **不要给大文件建巨型 documentView**：`NSScrollView` 里放 500 万行 × 19pt = 1 亿 pt 的文档视图会引发坐标/精度与绘制问题，改为固定视口 + 自绘 + 手动滚动条映射。
21. **自绘 NSView 只填 `dirtyRect ∩ bounds`**：与行号侧栏同一个坑，否则会把上方 Tab 栏一起刷掉。
22. **不要比较整份文档字符串**：`NSTextView.string` 返回 UTF-16 桥接串，与原生 UTF-8 `String` 比较会走 NFC 归一化；8.7 MB 一次约 650 ms。`isDirty`、视图同步、高亮回调一律用版本号 / token / 长度这类 O(1) 判据，`isDirty` 用 `revision != savedRevision`。
20. **超长行是 TextKit 1 的死穴**：单行 9 MB 首次排版 2.6 s，宽度变化还会再触发 2.7 s 重排；超过 5 万字符的行改为只读折行预览（每 160 字符硬换行），首屏降到约 20 ms，可手动切回可编辑（关闭自动换行）。
21. **行号扫描成本**：20 万行约 80 ms。已在编辑时防抖 150 ms，并在主线程复制 UTF-16 缓冲后放到后台扫描，后台不触碰 NSTextStorage。
22. **自定义 NSView 不要填满 `dirtyRect`**：`NSViewRepresentable` 交回裸 `NSView` 的脏区可能大于该视图自身的帧，`dirtyRect.fill()` 会把兄弟 SwiftUI 视图（如 Tab 栏）一起刷成背景色，表现为“打开代码文件时标签栏消失、切到 Markdown 又回来”。侧栏只画数字和分隔线，并用 `dirtyRect.intersection(bounds)` 裁剪；背景交给外层 `.background`。同一棵视图树里换成 `NSScrollView` 承载则不会出现该问题。
20. **Vue 与正则的开销**：`.vue` 每次重算需要 `1 + 区块数` 次全量解析，正则路径每个规则一次全文扫描，因此沿用与 tree-sitter 相同的 1,000,000 UTF-16 上限；超出后统一退化为纯文本。

## 验证记录

- 使用相同版本依赖完成 Debug 与 Release 构建（Xcode 27.1，arm64）。
- Release 产物已接入白底 AppIcon，完成 ad-hoc 签名与启动验证；已生成 1.5.2 的 zip 与 DMG。
- 已通过 LaunchServices 端到端验证：向测试包发送 `readme.md` 打开事件后，应用成功创建并显示对应 Tab。
- 已在系统 LaunchServices 中看到 TextCove 注册的 Markdown、JS、TS、HTML、CSS、Java、C、Swift、YAML、JSON、plist 与通用文本类型。
- tree-sitter 探针覆盖 md/js/html/css/java/yml/json；C、Swift、TypeScript 通过文件 URL 自动匹配 grammar。新增 `.ts`、`.plist`、`.txt` 已在验证工程中成功打开并显示行号。
- 通过完整 SwiftUI App 的离屏窗口验证，代码正文与行号同时渲染且逐行对齐；Markdown 预览的 fenced 与 indented 代码块行号也已确认。
- 27 项模型级测试通过：路径去重、选中已有 Tab、异步读取、脏状态、保存二次确认、原子保存、JSON 格式化/压缩、JSON 错误行列、读取失败、文件夹拖入、关闭脏 Tab 等。
- 离屏渲染真实 SwiftUI 视图验证了欢迎页、Markdown 预览、Markdown 编辑、本地图片、任务列表、浅/深色主题、JS/C/Swift/TypeScript/plist/纯文本编辑视图和真实窗口工具栏。由于 AppKit 图层不会进入普通窗口截图，代码编辑器的行号对齐另行用 PDF 渲染核对。
- XCUITest 因本机未授予 macOS 自动化（Accessibility）权限，未能执行完整的鼠标点击测试；“打开面板选择文件 / 系统级拖拽 / 原生弹窗点击”属于该边界，交互逻辑由模型测试和原生控件保证。
- Finder 默认应用仍需要用户通过“显示简介 → 全部更改”授权一次，这是 macOS 的默认应用策略。

### 1.3.0 语言与文本覆盖验证

- 探针直接编译 App 内的 `FileKind` / `SyntaxHighlighter` / `VueHighlighter` / `RegexHighlighter` 源文件，对 11 个样本产出 token 并检查区间越界，结果全部为 0。
- Vue 分区投影断言：`<script setup lang="ts">` 正文 106 个 token、`<style scoped>` 正文 27 个；`interface`、`function` 被识别为关键字；HTML 语法没有漏染 script/style 正文（style 内出现的 `tag="button"` 来自 CSS 元素选择器，属预期）。
- shebang / modeline：无扩展名的 `deploy`（`#!/usr/bin/env python3`）被识别为 Python 并产出 75 个 token；`start.sh` 走 bash，且其中的 `# vim: ft=ruby` 不会覆盖扩展名的判定结果（URL 优先级更高）。
- 正则规则：diff 五类（command / header / chunk / inserted / deleted）、XML 注释与 PI 与实体、plist 的 `<key>` 属性色、nginx 指令与 `$host`、GraphQL 关键字 / 类型 / 字段、env 的 export / 键 / 值 / 插值、gitignore 的注释 / `!` / 通配符均按预期命中。
- 编码回退：37 字节的 GBK 文本解码为 21 个 UTF-16 单位，回写仍是 GBK；UTF-16/UTF-32 通过 BOM 分支识别。
- 离屏渲染 10 个样本（Vue、XML、plist、diff、nginx、GraphQL、.gitignore、.env、python、shell）确认代码正文与行号同时可见、颜色符合预期。
- Release 通用二进制（arm64 + x86_64）构建成功；ad-hoc 签名后用 `open -n -a` 同时打开 `App.vue` 与 `schema.graphql`，进程稳定存活；已 `lsregister -f` 重新登记 15 组文档类型。
### 1.5.0 超大文件查看器验证

- 目标文件：一个 1.12 GB 的 Navicat MySQL dump（5,217,685 行、CRLF、UTF-8、最长行 33,162 字节）。
- 实测：mmap + 视图创建 15 ms，首帧 12 ms，后台索引 0.4–0.5 s（页缓存热），常驻内存 33 MB → 约 100 MB 后稳定；滚动重绘 40 行约 2.7 ms；定位到 1/3 处 <1 ms。
- 真实 App 端到端：用 `open -n -a TextCove.app <dump.sql>` 打开该文件，3 s 内 RSS 112 MB，索引完成后 CPU 归零。
- 过程中修正两个问题：稀疏索引内层把「相对偏移」当绝对位置导致死循环；用 mmap 建索引会让 RSS 涨到 2.3 GB（改为 `pread` + `madvise`）。

- 1.5.2 补充验证：长行折行（3,000 字符 INSERT 折成多行、无右缘截断）、拖选/⌘C 复制（剪贴板内容为完整原始行）、进度浮层（0.12 s 时截到「26% + 进度条」）；滚动 30 帧平均 1.36 ms/帧。
- 1.5.1 补充验证：`onIndexProgress` 回调 51 次（2%→100%，单调递增），索引 737 ms 内完成；说明栏进度条随之后切为完成态。

### 1.4.1 大文件性能验证

- 真实 `ContentView` + 真实窗口，打开 `node_modules/typescript/lib/typescript.js`（8.72 MB / 201,040 行）：打开 → 首次可交互 **0.5 s**（修复前主线程出现 714 + 823 + 1115 ms 三次卡顿），关闭 **约 1 ms**，期间无 >100 ms 的主线程停顿。
- 单行 8.6 MB 压缩产物：自动进入只读折行预览，0.8 s 可交互、无卡顿；「编辑原文件」可切回可编辑（关闭自动换行）。
- 小文件回归：仍可编辑、保存按钮与 `*` 标记正常、行号与语法高亮正常。
- 采样确认根因：`_stringCompareSlow` → `Unicode._NFCNormalizer`，调用点分别是 `isDirty`、视图文本同步与高亮回调的 `textView.string == snapshot`。

### 1.4.0 界面改版验证

- 真实 `NSWindow` + unified 工具栏下渲染 `ContentView` 截图核对四种状态：Markdown 预览（浅色）、Markdown 编辑（浅色）、代码文件（深色）、Markdown 预览（深色）。Tab 栏下方无分隔线，正文为圆角卡片，右下角悬浮胶囊的选中态与图标可见，本地相对图片仍然正常加载。

### 1.3.1 Tab 栏遮挡修复验证

- 用最小复现工程确认根因：同一个 `VStack` 里放一个只 `dirtyRect.fill()` 的裸 `NSView`，上方的 40pt 色条即被刷白；改成“什么都不画”或“只画小图形”后色条恢复正常，`NSScrollView` 承载则始终正常。行号侧栏按此修改。
- 用真实 `NSWindow` + unified 工具栏直接渲染 `ContentView` 截图核对：浅色与深色下 `.vue` 的标签、行号、Vue 分区高亮同时可见；打开 Markdown 后再切回 `.vue`，标签仍然可见。
- 边界不变：本机仍无法执行 XCUITest 鼠标级测试，真实窗口截图受屏幕录制权限限制，代码渲染统一用离屏 `NSHostingView` 验证。

## 第三方许可

- CodeEditLanguages — MIT
- SwiftTreeSitter — MIT
- tree-sitter — MIT
- markdown-it — MIT
- js-beautify — MIT

打包进 App 的 JavaScript 依赖完整许可证见 `TextCove/Resources/THIRD_PARTY_NOTICES.txt`。
