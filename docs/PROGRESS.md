# NetNewsWire Translation — Progress Log

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

**累计测试:** 36 passing

---

## 待办 Issues

### Issue #6 — Mac Preferences/Translation/ UI
- 新建 Mac/Preferences/Translation/TranslationPreferencesViewController.swift
- 控件:
  - Enable toggle
  - Target language popup
  - Engine segmented control
  - OpenAI sub-settings (base URL/API key/model/测试连接)
  - Skip-when-source-matches-target toggle
- 需要 NSViewController + NSUserDefaultsController 绑定

### Issue #8 — WebViewController + JS bridge + status indicator + retry
- 编辑 Mac/Article/ArticleViewController.swift
- 注入 TranslationCoordinator
- 在 webView 加载完成后调用 coordinator.translation(for:...)
- 实现 updateTranslation(...) JS bridge
- 添加状态指示器 (idle/translating/translated/failed)
- 实现 retry 按钮

### Issue #9 — Display mode toggle (译文/对照/原文)
- 添加 segmented control 到 article toolbar
- 三态: translation-only / bilingual / original-only
- JS 调用切换显示

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
