# NetNewsWire Translation — Progress Log

## 2026-10-26 — 翻译中不再显示源码，改为过渡动画

用户反馈翻译时界面很丑，直接露出了 HTML 源码：翻译引擎返回的是 HTML，
流式到达时被当成纯文本转义显示，于是文章视图里出现
`<p><strong>工具：</strong> <a href="…">Seam Cutter</a></p>`。
原定的打字机效果打在这份源码上，等于把难看放大。

**改法**：翻译进行中不再渲染任何译文内容，改用骨架微光占位。

- `Mac/MainWindow/Detail/DetailWebViewController.swift`：
  - `.translating` 分支：删掉 `translationStreamHTML` + `translationStreamingScript`，
    换成 `translationSkeletonHTML`（6 条占位线）
  - 删除 `translationStreamingScript`（`setTranslationStreamText` /
    `appendTranslationStreamDelta` 两个 JS 桥）、`renderPendingTranslationStream()`、
    `javascriptStringLiteral(_:)`，以及 `didFinish` 里的旧调用
  - `receiveTranslationDelta(_:)` 改为只累积，不再往 web view 推文本
  - `.streamingFailed` 分支：残留的半截译文先剥标签再显示（`translationPartialHTML`），
    失败路径同样不出现源码
- `Shared/Article Rendering/core.css`：
  - 新增 `.translationSkeleton` / `.translationSkeletonLine`：用 `currentColor`
    画的微光扫过动画，所有主题自动跟随，无需主题专属规则
  - 新增 `.translatedArticleBody` 淡入（`nnwTranslationFadeIn`），译文到位时
    覆盖在占位符上
  - 新增 `.translationPartial`：失败时的纯文本残片
  - `prefers-reduced-motion: reduce` 下关掉扫光与淡入
- `Tests/NetNewsWireTests/DetailWebViewControllerTranslationTests.swift`：
  - 「Translating status renders streamed text safely」改为
    「Translating state shows a placeholder instead of raw markup」：
    断言占位符出现，且页面里没有 `data-translation-stream`、没有 `<p><strong>`
  - 新增「Failed stream shows the partial translation as plain text」：
    断言残片是纯文本、没有 `<a>` 标签
- 文档：ADR 0004 改写（流式内容不再进正文）、新增 ADR 0005、
  `Technotes/Translation.markdown` 决策表加第 18 条与两条 QA 项

### 占位条第一次没显示出来（div 高度被全局重置吃掉）

用户装包实测反馈「没看到动画」——截图里 "Translating" 下面是一大片空白，
一根条子都没有。

原因不在新样式，在共享样式表 `Shared/Article Rendering/stylesheet.css`：

```css
img, figure, video, div, object {
	max-width: 100%;
	height: auto !important;   /* ← 干掉所有 div 的显式高度 */
	margin: 0 auto;
}
```

占位条本来是空的 `<div>`，高度被这条 `!important` 重置成 `auto`，
空 div 高度就塌成 0 —— 只剩 margin 撑出来的那段空白。

修法：占位条从 `<div>` 改成 `<span class="translationSkeletonLine">`
（`display: block`）。`span` 不在那条重置的选择器里，高度不会被清掉。

**教训**：这个仓库的共享样式表有一条针对 `div` 的全局重置，任何"空 div +
显式高度"的骨架/占位方案都会中招。写这类东西要先看 `stylesheet.css`。

**回归测试**：新增「The translating placeholder is actually visible」——
在真实 WKWebView 里断言占位条 `getBoundingClientRect()` 宽高都 > 0、
`::before` 的 opacity > 0。变异体回测确认有效：把 `<span>` 改回 `<div>`，
该测试立刻失败。

另外发现测试 harness 的 web view 没有视口宽度（`innerWidth == 0`），
百分比宽度会全部塌成 0 —— 断言可视性前得先给 `webView.frame` 赋一个真实尺寸。

**版本**：7.2.3 → **7.2.4**（build 7112 → 7113），发行说明补 7.2.4。
之前测试用的两个包都是 7.2.3/7112（一个坏一个好），版本号必须能区分开，
否则 Sparkle 会当成同一个版本。

同时补了一条回归测试「The translating placeholder is actually visible」，
在真实 WKWebView 里断言占位条的 `getBoundingClientRect()` 宽高都大于 0、
`::before` 的 opacity 大于 0。变异体回测确认有效：把 `<span>` 改回 `<div>`，
该测试立刻失败。

另外发现测试 harness 的 web view 没有视口宽度（`innerWidth == 0`），
百分比宽度会全部塌成 0 —— 断言可视性前得先给 `webView.frame` 赋一个真实尺寸。

**取舍**：读者看不到译文逐字到达，改为在动画后等待。这是刻意的 —— 另一种做法
是把流当活 HTML 注入页面，既有净化问题，也会被半截标签搞出闪烁。

## 2026-10-21 — About 面板归属 + 评论模块崩溃加固

### About 面板

用户说明这是个人复刻魔改版本，About 面板的作者应当是他本人（along），
并要展示他的 git 地址。

- `Mac/Resources/Info.plist`：
  - `NSHumanReadableCopyright` → `Copyright © 2002-2026 Brent Simmons. All rights reserved. This version © 2026 along.`
  - 新增 `NNWVersionAuthor`（`along`）与 `NNWVersionAuthorURL`
    （`https://github.com/chenweil/NetNewsWire`）
- `Mac/About/AboutWindowController.swift`：
  - 版权行里把 `along` 链到他的仓库地址（原上游作者的链接保留 —— MIT 许可
    要求保留原版权声明）
  - 原来那个醒目的 `netnewswire.com` 链接换成 `github.com/chenweil/NetNewsWire`
  - 顺带修掉三处强制解包（`NSHumanReadableCopyright` 取值、`inessential.com`、
    `netnewswire.com`）
- `Mac/Resources/Credits.rtf`：致谢列表最前面加一条「This Version → along」，
  带仓库链接
- 版本 7.2.1 → **7.2.2**（build 7110 → 7111），发行说明补 7.2.2

### About 面板的版权行被裁（7.2.3）

装上 7.2.2 截图后发现：版权行第三行被切掉一半。

原因不在代码，在 xib 的手工布局：版权文本框
`AboutWindowController.xib` 里被钉死成 181×32（`verticallyResizable="NO"`，
`maxSize` 高度 32），而文案从 56 字变成 84 字之后，181pt 宽度下要排 3 行
（需 42pt），框只有 32pt。

用 CoreText 实测了不同宽度下的行数：

| 宽度 | 原版权行 | 新版权行 |
|---|---|---|
| 181 pt | 2 行 | **3 行**（需 42pt > 32pt）→ 被裁 |
| 240 pt | 2 行 | 2 行（需 28pt ≤ 32pt）✓ |
| 249 pt | 2 行 | 2 行 ✓ |

修法：把 About 窗口从 490 加宽到 560，版权框 181 → **249 pt**，左栏各元素
（图标、标题、版本号、网址）按新的 142.5pt 中线重新居中，高度不动。

补了一条回归测试 `copyrightFitsItsLabel`：**直接从 xib 里读出**版权框的
宽高，再用 CoreText 排版权文案，断言行数 × 行高不超过框高。这样以后版权
文案再加长就会直接测红，而不是等装到机器上才看得出来。已做红绿验证：
把宽度改回 181，测试报 `42.0 <= 32.0` 失败；改回 249 通过。

版本 7.2.2 → **7.2.3**（build 7111 → 7112），发行说明补 7.2.3

### 评论模块的崩溃加固

用户发来两份测试宿主崩溃日志（14:17 / 14:18，本轮改动之前的版本）：

| 时间 | 现象 |
|---|---|
| 14:17 | `EXC_BREAKPOINT`，`Array.subscript.getter` 越界（`Array._checkSubscript`） |
| 14:18 | `EXC_CRASH` SIGABRT，`-[__NSCFNumber count]: unrecognized selector` |

两个都是**野指针特征**（读到了已释放/被写坏的对象），不是普通断言失败。
排查后按「能确定的问题直接修」处理：

1. **`HTMLElement.parent` 是只写不读的死代码，而且是个 `weak` 引用** ——
   弱引用正是这类野指针的经典来源。直接删掉（`attach()` 里那一行赋值也没了）
2. **解析器的字符串切片没有边界保护** —— `finish()` 里
   `html[element.openTagEnd..<innerEnd]`，遇到乱序索引会直接越界。
   改成先夹紧索引再切片
3. **测试桩的响应表是全局共享的，且用「首个 URL 包含即命中」的模糊匹配** ——
   并行测试之间可能互相串台。改成**按完整 URL 精确匹配**，
   并让 provider 暴露 `repliesEndpoint(topicID:)` / `topicPageURL(topicID:)`
   两个 URL 构造器，测试直接用同一套构造，不会因为 provider 改 URL 而失配
4. **补了一个并发护栏测试**：50 个 task 同时打同一个 topic，断言结果一致

### 验证

- 复现尝试：独立程序把三种 topic（JSON 路径 / HTML 回退 / 空回复）并发跑 400 轮，
  **未复现**；加固后完整套件连跑两次均 `** TEST SUCCEEDED **`
- 诚实说明：**崩溃的精确触发条件没有定位到**。已排除的假设：解析器状态共享
  （解析器无共享可变状态）、响应表串台（每个 topic 用唯一 ID + 现在精确匹配）、
  简单的并发写竞争（400 轮并发未复现）。已修掉的是**能确认存在的弱引用与
  越界风险**，其余按「测试层问题、不阻塞进度」处理

## 2026-10-21 — 评论线程版式重做

### 问题

用户看 V2EX 评论的第一版截图后提出「样式能否调整下，更好看些」。实际问题是
**版式坏掉了**，不是配色不够好：

1. **作者名跑到页面中间，时间戳被甩到最右**。根因是基础主题里的
   `img, figure, video, div, object { margin: 0 auto }`：`.articleCommentAuthorCell`
   是个 `div`，又是 flex item，auto margin 把剩余空间全吃掉 → 居中；
   日期 span 没有 auto margin → 顶到最右。
2. **每个评论正文下面挂一个孤零零的 `#`**（permalink 单独一行），像乱码。
3. **评论之间没有分隔**，一整篇糊成一片，扫不出边界。
4. **评论正文和文章正文同字号**，读者分不清「作者写的」和「网友说的」。

### 实现内容

**设计取向**：把评论线程做成**转录本（transcript）**——文章是正文，评论是附注。
- 左侧一条**编号装订线**，每条评论的序号用等宽字体，兼作跳转到原站评论的链接
- 头像靠左，**作者名与时间戳同行**（时间紧跟作者，不再跑到最右）
- 评论块用**自己的字号层级**（0.95em 容器 / 正文 0.93em），明确矮于文章正文
- 回复**缩进并挂在一条发丝导轨下**，头像更小
- 段落间距收紧、`p:last-child` 去掉下边距
- 时间戳用 `<time datetime>` 输出，机器可读
- 没有头像时用**姓名首字母徽章**兜底
- 去掉灰底色块，只用留白 + 细线分段（深色模式同样成立）

**代码改动**
- `Shared/Comments/CommentsHTMLRenderer.swift`：重写结构（编号、`<time>`、
  首字母徽章、语义化 header）
- `Shared/Article Rendering/core.css`：重写 `.articleComments*` 全部样式，
  跟随主题变量（`--article-title-color` / `--article-date-color` /
  `--table-cell-border-color` / `--accent-color`），所有主题都生效

**顺带修掉的两个连带问题**
- **X-Large / XX-Large 字号从来没生效过**：`ArticleTextSize.cssClass` 返回的是
  `xLargeText` / `xxLargeText`，而**全部 9 个主题**（含基础主题）定义的类名是
  `.xlargeText` / `.xxlargeText`（小写 l）—— 类名对不上，样式不命中。
  另外 `.xxlarge` 原本也返回 `xLargeText`（复制粘贴漏改）。
  补了 `ArticleTextSizeTests`：逐个字号断言主题样式表里存在对应规则，
  以后再改名会直接测试失败
- **评论不跟随文章的字号设置**：评论块是 `<article>` 的兄弟节点，拿不到
  `#bodyContainer` 上的字号类；用户选「小」字号时评论反而比正文还大。
  改成外层套一个带字号类的 wrapper，评论块用 `0.95em` 相对它缩放

### 版本与提交

- 版本号 7.1.2 → **7.2.1**（build 7108 → 7110）；发行说明补 7.2.1 / 7.2.0 两条
- 提交拆成三个（分支 `chenwl`）：
  1. `fix: make the translation display mode work when the article has no translation`
  2. `feat: show comment threads for V2EX topics`
  3. `feat: redesign the comment thread as a transcript`（含字号修复与版本）

### 验证方式

搭了一套**可复现的视觉回路**（`/tmp/nnw-preview`，临时文件）：
把 `Shared/Comments/` 真实源码 + 真实 `core.css` + 真实主题 CSS 编译成独立程序，
拉**线上真实 V2EX 回复**渲染成整页 HTML，再用 headless Chrome 截图，
改一版看一版。字体/分支差异也在这里校准（预览要显式展开主题 CSS 的
macOS 分支并替换 `[[font-size]]`，否则 headless Chrome 会落回 Times）。

### 已知限制

- 回复嵌套每层缩进约 50pt，两层以上会明显变窄（V2EX 本身是平铺的，
  实际用不到）
- 编号是**线程内位置**，不是站点自己的楼层号

## 2026-10-21 — 评论展示 + 翻译显示模式修复

### 问题

1. **看不到评论**：V2EX 等论坛的 RSS 只带首帖正文，回复（评论）不在 feed 里，
   NetNewsWire 原本没有任何抓取评论的能力。
2. **Translation / Bilingual / Original 切换「没反应」**：机制本身是好的
   （单元测试证明 JS 桥接函数存在且能正确切换可见性），真正的原因是
   **文章没有译文时这个开关无事可做**，而 UI 不给任何提示：
   - `TranslationStatus` 没有 `skipped` 分支，协调器返回的
     `SkipReason`（`.disabled` / `.sourceMatchesTarget`）被直接丢弃成 `.idle`；
   - 用户偏好里 `translation.skipWhenSourceMatchesTarget = true`、
     目标语言 `zh-Hans`，读中文文章时必然跳过翻译 —— 开关永远按不动。

### 实现内容

**翻译显示模式修复**
- `TranslationStatus` 新增 `.skipped(SkipReason)`，跳过原因不再丢失
- `TranslationCoordinator.localSkipReason(for:bodyHTML:)`：纯本地判定，
  不查缓存、不联网、不调引擎（配合 `SourceLanguageInspector`）
- 文章视图新增状态行：翻译关闭 / 原文已是目标语言
- 显示模式改为**渲染时生效**（服务端直接写 `hidden` 属性），
  不再依赖文章页 JavaScript；切换时先走 JS 桥接（秒级、不重播打字机动画），
  桥接不可用时回退到重新渲染
- 工具栏 segmented control 在当前文章**没有译文时置灰**，
  tooltip 说明原因 —— 不再出现「点了没反应」的死控件

**评论抓取（Shared/Comments/）**
- `ArticleComment`：评论模型（作者、头像、正文、时间、permalink、嵌套回复）
- `CommentsProvider`：扩展点协议（`canProvideComments` / `fetchComments`）
- `CommentsService`：按 URL 选 provider + 会话内缓存；
  **没有任何 provider 认领的 URL 不会产生任何网络请求**
- `V2EXCommentsProvider`：优先走 `api/replies/show.json`，
  失败时回退解析主题页 HTML
- `HTMLElementParser`：轻量 HTML 解析器（属性、嵌套、innerHTML、raw-text 跳过）
- `CommentHTMLSanitizer`：剥掉 script / on* 事件 / `javascript:` URL
- `CommentsHTMLRenderer`：渲染成文章视图里的评论块
- 样式写在 `core.css`（所有主题都包含），跟随主题变量

**偏好设置与版本**
- Preferences → Translation 新增「Display Mode」下拉框 —— 工具栏控件在文章无译文时
  是置灰的，模式仍要能设置
- 工具栏控件通过 `DetailWebViewController.onTranslationAvailabilityChanged` → 
  `DetailViewController` → `MainWindowController` 三级回调拿到可用性
- 版本号 7.1.2 → **7.2.0**（build 7108 → 7109），发行说明已补

**顺带修掉的老问题**
- 切文章时上一篇文章的译文会闪一下：先重置 `translationStatus` 再渲染
- 多次异步重渲染会乱序到达，导致页面显示旧状态：加了 `reloadToken`，
  只有最后一次请求才渲染

### 测试

- `CommentsTests`：HTML 解析器、消毒器、V2EX JSON/HTML 两条路径、
  provider 选择、渲染与转义
- 翻译测试：跳过原因上报、显示模式在不启用文章 JS 时仍生效
- 真实站点端到端验证：V2EX 主题 1249625 两条路径都取到 5 条回复，
  与另一个 RSS 工具显示的一致

### 已知限制

- Flarum 系论坛（linux.do / linux.sb / w2solo）读不到回帖：帖子由前端渲染，
  服务端 HTML 无正文，公开 API 全部 404
- 其余站点要加评论 = 加一个 `CommentsProvider`，文章视图不用改

## 2026-10-08 — Issue #9 Complete ✅

### 实现内容

**TranslationDisplayMode** (Shared/Translation/TranslationEngine.swift)
- 三态枚举: `translation`（默认）/ `bilingual` / `original`
- 持久化在 `TranslationSettings.displayMode`（key: `translation.displayMode`）

**DetailWebViewController.swift**
- `.translated` 状态一次性渲染三个内容块: 译文标题头 + 原文 body（`data-translation-mode-content="original"`）+ `<hr>` 分隔线 + 译文 body
- 新增 JS bridge `window.setTranslationDisplayMode(mode)`: 切换仅改可见性，不重新 fetch、不重新渲染
- 新增 `setTranslationDisplayMode(_:)` 公开方法；模式变更经 DetailViewController 从工具栏转发
- 顺带重构: `currentBodyInfo` helper 统一 feed body / extracted body 的取值（request / retry / render 三处复用）

**MainWindowController.swift**
- 新增 toolbar item `.translationDisplayMode`（NSSegmentedControl, 三段: Translation / Bilingual / Original）
- `changeTranslationDisplayMode(_:)` action 转发到 DetailViewController
- 老用户一次性安装逻辑 `installTranslationDisplayModeToolbarItemIfNeeded`（独立 UserDefaults flag，插在 Translate 按钮右侧）
- 已加入 toolbarAllowedItemIdentifiers / toolbarDefaultItemIdentifiers

**测试**: 49 tests / 5 suites 全绿（新增 3 个 displayMode 设置测试）

```
Test run with 49 tests in 5 suites passed after 0.042 seconds
```

### 技术要点

1. **无 re-fetch 切换**: 三个内容块都在 `.translated` HTML 里，JS 只切 `hidden`，满足 PRD F-10 "updates the view without re-fetching"
2. **初始模式**: 渲染时由 Swift 把当前模式写进 script，首次加载即生效
3. **打字机效果兼容**: typewriter 只作用于译文块，切模式不重启动画
4. **流式输出补记**: 此前 streaming（`streamingTranslation` / `streamingRetry` / `streamingFailed` 状态、JS 流式渲染）已实现并通过测试，但未记录在案，现补记

---

## 2026-06-28 23:19 — Issue #7 Complete ✅

### 实现内容

**Preferences.storyboard** (已更新)
- 添加 Translation scene (storyboardID: "Translation")
- 连接到 TranslationPreferencesViewController
- View 尺寸: 512x400 (standard preferences width)

**构建结果**

```
** BUILD SUCCEEDED **
```

### 技术要点

1. **Storyboard scene**: 最小化定义
   - 仅包含 view controller 和空 view
   - UI 由 TranslationPreferencesViewController 代码创建
   - Storyboard 只用于 scene discovery 和 toolbar routing

2. **Scene ID**: "TR1-TR-Translation", "TR2-VC-Translation", etc.
   - 使用 TR 前缀避免与现有 IDs 冲突

3. **Canvas position**: y=737 (位于 Advanced scene 下方)

---

## 2026-06-28 23:17 — Issue #6 Complete ✅

### 实现内容

**TranslationPreferencesViewController.swift** (558 lines)
- 纯代码 UI (无 storyboard/xib)
- Enable toggle (绑定 `translation.enabled`)
- Target language popup (13 种常用语言)
- Engine segmented control (Apple / OpenAI-Compatible)
- Skip-when-source-matches-target toggle
- OpenAI sub-settings group:
  - Base URL text field
  - API key secure text field (Keychain 存储)
  - Model text field
  - Test connection button

**PreferencesWindowController.swift** (已更新)
- 添加 `ToolbarItemIdentifier.Translation`
- 添加第四个 toolbar item (SF Symbol: character.bubble)

### 构建结果

```
** BUILD SUCCEEDED **
```

### 技术要点

1. **Keychain 集成**: 使用 `CredentialsManager` 存储 API key
   - Server: `translation.openai-compatible`
   - Username: `api-key`
   - Type: `CredentialsType.openAICompatibleAPIKey`

2. **UI 控件**: 纯代码创建 (AppKit + Auto Layout)
   - 无 IBOutlet/IBAction
   - 使用 `#selector` 绑定 actions
   - 标准间距: 20px padding, 8px field spacing

3. **Test Connection**: 实时测试 OpenAI API 连接
   - 发送简单的翻译请求 (`Hello` -> `zh-Hans`)
   - 显示成功/失败提示

4. **State Management**: UserDefaults 绑定
   - 实时读取/写入设置
   - `isUpdatingUI` 标志防止循环更新

---

## 2026-06-28 22:57 — Issue #5 Complete ✅

### 测试结果

```
Test run with 36 tests in 5 suites passed after 0.022 seconds
```

**详细统计:**
- TranslationSettingsTests: 6 tests ✅
- AppleTranslationEngineTests: 7 tests ✅
- SourceLanguageInspectorTests: 8 tests ✅
- OpenAICompatibleEngineTests: 7 tests ✅
- TranslationCoordinatorTests: 8 tests ✅

**总计:** 36 tests passing

### Issue #5 完成情况

TranslationCoordinator 的核心功能已实现并通过测试：

1. ✅ 禁用状态返回 skipped
2. ✅ 缓存命中返回缓存结果（不调用引擎）
3. ✅ 短文本（<1500字符）使用 Apple Translation
4. ✅ 长文本（≥1500字符）且有 API key 时使用 OpenAI
5. ✅ 长文本但无 API key 时回退到 Apple Translation
6. ✅ 源语言匹配目标语言时跳过翻译（不写缓存）
7. ✅ 目标语言变更产生不同的缓存键
8. ✅ 短文本即使有 API key 也使用 Apple Translation

### 架构亮点

- **DI via closures**: 所有依赖通过闭包注入，便于测试
- **Sendable compliance**: Swift 6 strict concurrency 支持
- **Engine selection logic**: 清晰的引擎选择规则（<1500 用 Apple，≥1500 用 LLM）
- **Cache management**: 自动缓存和 retry 时的缓存清除

---

## 已完成 Issues

| Issue | 名称 | 文件 | 测试数 | 状态 |
|-------|------|------|--------|------|
| #0 | DB 层 | Modules/ArticlesDatabase/.../Translation.swift | N/A | ✅ DONE |
| #1 | Translation types + engine protocol | Shared/Translation/TranslationEngine.swift | 6 | ✅ DONE |
| #2 | AppleTranslationEngine | Shared/Translation/AppleTranslationEngine.swift | 7 | ✅ DONE |
| #3 | SourceLanguageInspector | Shared/Translation/SourceLanguageInspector.swift | 8 | ✅ DONE |
| #4 | OpenAICompatibleEngine | Shared/Translation/OpenAICompatibleEngine.swift | 7 | ✅ DONE |
| #5 | TranslationCoordinator | Shared/Translation/TranslationCoordinator.swift | 8 | ✅ DONE |
| #6 | Mac Preferences/Translation/ UI | Mac/Preferences/Translation/TranslationPreferencesViewController.swift | N/A | ✅ DONE |
| #7 | PreferencesWindowController toolbar 注册 | Mac/Base.lproj/Preferences.storyboard | N/A | ✅ DONE |
| #8 | WebViewController + JS bridge + streaming + retry | Mac/MainWindow/Detail/DetailWebViewController.swift | N/A | ✅ DONE |
| #9 | Display mode toggle (译文/对照/原文) | MainWindowController + DetailWebViewController | 3 | ✅ DONE |

**累计测试:** 49 passing

---

## 待办 Issues

### Issue #10 — Manual QA pass
- 按 PRD acceptance checklist (11 项) 验收
- 测试项:
  - Enable/disable
  - Target language switch
  - Engine switch
  - Cache hit/miss
  - Source-lang skip
  - Long text LLM fallback
  - API key missing fallback
  - Retry
  - Display mode toggle

---

## 关键决策记录

1. **命名约定** (避免系统框架冲突)
   - 持久化记录类型: ArticleTranslation (非 Translation)
   - 引擎无关类型保留裸名: TranslationEngine, TranslationRequest, TranslationResult, etc.
   - 原因: macOS Translation framework 导出同名类型

2. **Apple Translation SDK 限制**
   - TranslationSession 是 macOS 15.0+
   - init(installedSource:target:) 是 macOS 26.0+
   - 解决方案: if #available(macOS 26.0, *) { ... } else { throw .languagePackUnavailable }

3. **模块分层**
   - Shared/Translation/*.swift → 编译进 macOS app target (非 SPM 模块)
   - import ArticlesDatabase 引用 ArticleTranslation.BodySource

4. **Keychain 存储 API key**
   - Server: "translation.openai-compatible"
   - Username: "api-key"
   - Type: CredentialsType.openAICompatibleAPIKey

5. **架构决策 (ADR)**
   - ADR-0001: Apple Translation as primary engine (on-device, zero cost)
   - ADR-0002: LLM long-text fallback (≥1500 chars, OpenAI-compatible)
   - ADR-0003: OpenAI-compatible HTTP client (可配置 base URL/model)

6. **Scope 限制**
   - Mac-only (用户: "我不打算开发 ios")
   - 代码放 Shared/ 保持可测性,但只 wire Mac UI
   - 无 onboarding,默认关闭,release notes 说明

7. **测试策略**
   - 仅单元测试 (36 tests)
   - UI/Apple Translation/OpenAI 调用/JS bridge 均手动 QA
   - Mock engine via DI closure

---

## 环境信息

- macOS: 15.7.4 (arm64)
- Xcode: 26.1
- SDK: macOS 26.1
- Swift: 6.2 (strict concurrency)
- Code signing: 无 Apple Developer account → CODE_SIGNING_ALLOWED=NO
- 测试框架: Swift Testing (@Suite, @Test, #expect)

---

## 命令速查

```bash
# 运行所有翻译测试
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:NetNewsWireTests/TranslationSettingsTests \
  -only-testing:NetNewsWireTests/AppleTranslationEngineTests \
  -only-testing:NetNewsWireTests/SourceLanguageInspectorTests \
  -only-testing:NetNewsWireTests/OpenAICompatibleEngineTests \
  -only-testing:NetNewsWireTests/TranslationCoordinatorTests \
  CODE_SIGNING_ALLOWED=NO test

# 清理 DerivedData (如遇到奇怪链接错误)
rm -rf ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*
```
