# Issues: Article Translation (Mac)

Tickets derived from [`0001-translation.md`](0001-translation.md). Each ticket is sized for one PR. Dependencies form a DAG; merge in order.

**Status legend:** `DONE` (already landed) · `READY` (spec'd, can start) · `BLOCKED` (waits on a dependency)

---

## #0 ArticlesDatabase persistence layer — **DONE**

**Size:** M
**Files:** `Modules/ArticlesDatabase/Sources/ArticlesDatabase/Constants.swift`, `Translation.swift` (new), `TranslationsTable.swift` (new), `ArticlesDatabase.swift`

**Description**
Persist cached translations in the Articles database, keyed by `(articleID, targetLanguage, bodySource)`, with a trigger to delete translations when articles are deleted.

**Acceptance criteria**
- [x] `translations` table created via `tableCreationStatements`
- [x] `Translation` struct exposed publicly (articleID, targetLanguage, bodySource, title, body, engine, translatedAt)
- [x] `TranslationsTable` with `fetchTranslation(...)`, `upsertTranslation(_:)`, `deleteTranslation(...)`
- [x] `articles_after_delete_trigger_delete_translations` trigger cleans up on article delete
- [x] Public API on `ArticlesDatabase`: `fetchTranslation`, `upsertTranslation`, `deleteTranslation`
- [x] `swift build` passes for `ArticlesDatabase` module

**Verification:** `cd Modules/ArticlesDatabase && swift build` → green. (Confirmed 28-06-2026.)

---

## #1 Translation types and engine protocol — **READY**

**Size:** S
**Depends on:** #0
**Files:** `Shared/Translation/TranslationEngine.swift` (new), `TranslationSettings.swift` (new)
**ADR:** none — pure types

**Description**
Define the engine-agnostic vocabulary: `TranslationRequest`, `TranslationResult` (translated / skipped / failed), `TranslationError`, `TranslationStatus`, `TranslationEngine` protocol, and a `TranslationSettings` wrapper over `UserDefaults` (read-side only — write-side comes in #5).

**Acceptance criteria**
- [ ] `TranslationEngine` protocol: `func translate(_ request: TranslationRequest) async throws -> Translation`
- [ ] `TranslationResult` enum with `translated(Translation)`, `skipped(SkipReason)`, `failed(TranslationError)`
- [ ] `TranslationError` covers `networkUnavailable`, `credentialsMissing`, `rateLimited`, `invalidResponse`, `translationFailed(String)`, `languagePackUnavailable(String)`
- [ ] `TranslationStatus` enum (`idle` / `translating` / `translated` / `failed(String)`) for the inline indicator
- [ ] `TranslationSettings` reads: `isEnabled`, `targetLanguage` (BCP-47 string), `engine` enum (`apple` / `openAICompatible`), `skipWhenSourceMatchesTarget`, `openAIBaseURL`, `openAIModel`
- [ ] `targetLanguage` defaults to `Locale.current.language.languageCode?.identifier` when unset
- [ ] Compiles cleanly; no engine implementations yet (protocol-only)

---

## #2 Apple Translation engine — **READY**

**Size:** M
**Depends on:** #1
**Files:** `Shared/Translation/AppleTranslationEngine.swift` (new)
**ADR:** [0001](../adr/0001-apple-translation-as-primary-engine.md)

**Description**
Wrap Apple's `Translation` framework as a `TranslationEngine`. Handles system UI for language pack download, surfaces pack-availability errors as `TranslationError.languagePackUnavailable`.

**Acceptance criteria**
- [ ] `AppleTranslationEngine: TranslationEngine`
- [ ] Translates a `TranslationRequest` whose body is < 1500 chars using `TranslationSession`
- [ ] Translates title and body as separate strings (not HTML round-trip)
- [ ] Returns `TranslationError.languagePackUnavailable(targetLanguage)` if `LanguageAvailability` reports the target is not yet downloaded and cannot be downloaded
- [ ] Surfaces system download UI when first invocation requires a language pack
- [ ] No network calls observable (verify with Network Link Conditioner)

**Verification:** Manual. Open an English article with translation enabled, Apple Translation should produce Chinese within ~2s; first-time target language shows system download sheet.

---

## #3 Source language detection — **READY**

**Size:** S
**Depends on:** #1
**Files:** `Shared/Translation/SourceLanguageInspector.swift` (new), `Tests/Translation/SourceLanguageInspectorTests.swift` (new)

**Description**
Wrap `NLTagger.dominantLanguage` to answer "does this text likely match the target language?" Sample the first ~500 characters of body and the full title.

**Acceptance criteria**
- [ ] `SourceLanguageInspector.matches(text:target:) -> Bool` returns true when dominant language equals target
- [ ] Samples only the first 500 chars of body (avoid full-text scan)
- [ ] Empty / whitespace input returns false (don't accidentally skip)
- [ ] Unit tests cover: pure English text + target=en → true; pure Chinese + target=zh-Hans → true; mixed Chinese-dominant + target=zh-Hans → true; pure English + target=zh-Hans → false; empty text → false

---

## #4 OpenAI-compatible engine — **READY**

**Size:** M
**Depends on:** #1
**Files:** `Shared/Translation/OpenAICompatibleEngine.swift` (new), `Modules/Secrets/Sources/Secrets/Credentials.swift` (extend `CredentialsType` enum)
**ADR:** [0003](../adr/0003-openai-compatible-http-client.md)

**Description**
HTTP client speaking OpenAI Chat Completions. Configurable `baseURL`, `apiKey`, `model`. API key stored via the existing `Secrets` module (extend `CredentialsType` with `.openAICompatibleAPIKey`). Translates title and body as separate strings; sends each in its own request so per-field failures are isolated.

**Acceptance criteria**
- [ ] `OpenAICompatibleEngine: TranslationEngine`, init takes `(baseURL: URL, apiKey: String, model: String)`
- [ ] System prompt instructs: "Translate from English to {target}. Preserve formatting. Output only the translation."
- [ ] Sends two requests per `TranslationRequest`: title → `translatedTitle`; body → `translatedBody` (sends as plain text, receives plain text; the engine treats body as opaque text not HTML)
- [ ] Returns `TranslationError.credentialsMissing` if apiKey is empty
- [ ] Returns `TranslationError.rateLimited` on HTTP 429
- [ ] Returns `TranslationError.networkUnavailable` on URL error
- [ ] Returns `TranslationError.invalidResponse` on non-2xx or unparseable JSON
- [ ] `CredentialsType.openAICompatibleAPIKey` added to `Secrets` module enum
- [ ] Timeout 30s; `temperature` 0.2 hardcoded for translation stability
- [ ] Unit test: `OpenAICompatibleEngine` with a mock `URLProtocol` returns a translated `Translation` for a fixture response; returns `rateLimited` on 429

---

## #5 TranslationCoordinator — **READY**

**Size:** L
**Depends on:** #1, #2, #3, #4
**Files:** `Shared/Translation/TranslationCoordinator.swift` (new)
**ADR:** [0002](../adr/0002-llm-long-text-fallback.md)

**Description**
Orchestrator. Per request: read settings → check cache → source-detect → engine-select (Apple default; OpenAI-compatible when body ≥ 1500 chars AND apiKey present) → translate → upsert → return result. Falls back to Apple when LLM is selected but credentials are missing, with an inline note.

**Acceptance criteria**
- [ ] `TranslationCoordinator` API:
  - `init(articlesDatabase: ArticlesDatabase, credentialsStore: CredentialsStore, defaults: UserDefaults)`
  - `func translation(for articleID: String, title: String, bodyHTML: String, bodySource: Translation.BodySource) async -> TranslationResult`
  - `func retry(articleID: String, title: String, bodyHTML: String, bodySource: Translation.BodySource) async -> TranslationResult`
- [ ] Returns `failed(.credentialsMissing)` only if LLM is selected AND key missing AND body ≥ 1500 chars; otherwise falls through to Apple
- [ ] Persists translation via `articlesDatabase.upsertTranslation(_:)` on success
- [ ] Engine selection threshold constant: `longTextThreshold = 1500`
- [ ] On retry: deletes existing cache entry then runs the same flow

**Unit tests (per PRD decision #17):**
- [ ] `test_disabled_returnsSkipped`
- [ ] `test_cacheHit_returnsCachedTranslation_withoutCallingEngine`
- [ ] `test_cacheMiss_appleEngineUsed_forShortText`
- [ ] `test_cacheMiss_llmEngineUsed_forLongText_whenKeyConfigured`
- [ ] `test_cacheMiss_fallsBackToApple_whenLLMKeyMissing`
- [ ] `test_sourceLanguageMatchesTarget_returnsSkipped_withoutCacheWrite`
- [ ] `test_targetLanguageChange_producesDifferentCacheKey` (re-fetch with different target returns miss → engine call)

---

## #6 Mac Preferences UI (Translation tab) — **READY**

**Size:** L
**Depends on:** #1, #4
**Files:** `Mac/Preferences/Translation/TranslationPreferencesViewController.swift` (new), `Mac/Preferences/Translation/TranslationPreferencesViewController.xib` or pure-code `NSStackView`, `Mac/Preferences/Translation/OpenAITranslationSettingsView.swift` (new)

**Description**
New `NSViewController` rendered in a new Preferences toolbar tab. Holds: enable toggle, target language popup, engine segmented control, conditional OpenAI fields (base URL, API key, model), test-connection button, skip-when-source-matches toggle.

**Acceptance criteria**
- [ ] Enable translation toggle (binds to `defaults.isEnabled`)
- [ ] Target language popup: System default / 中文(简体) / 中文(繁体) / English / 日本語 / 한국어 / Other… (reveals a text field for arbitrary BCP-47)
- [ ] Engine segmented control: Apple Translation / OpenAI-compatible
- [ ] OpenAI fields visible only when engine = OpenAI-compatible: `baseURL` (text), `apiKey` (secure field), `model` (text, placeholder `gpt-4o-mini`)
- [ ] `Test Connection` button sends a single-token ping (`"hi"`) and shows success/failure inline
- [ ] `Skip translation when source language already matches target language` toggle (binds to `defaults.skipWhenSourceMatchesTarget`)
- [ ] API key persists via `Secrets.CredentialsManager`; non-sensitive fields persist via `UserDefaults`
- [ ] All bind through `TranslationSettings` (write-side now implemented)

---

## #7 Preferences toolbar tab registration — **READY**

**Size:** S
**Depends on:** #6
**Files:** `Mac/Preferences/PreferencesWindowController.swift`, `Mac/Resources/Assets.xcassets/preferencesToolbarTranslation.imageset/` (new) or reuse an SF Symbol

**Description**
Register the new Translation preferences tab in the existing `PreferencesWindowController.toolbarItemSpecs`. Add icon, identifier, localized title.

**Acceptance criteria**
- [ ] `ToolbarItemIdentifier.Translation` constant added
- [ ] `toolbarItemSpecs` includes Translation entry with SF Symbol `character.bubble` or equivalent
- [ ] Window height adjusts to fit the new view (similar to how General/Accounts already do)
- [ ] Clicking the Translation toolbar item shows the new view controller from #6

---

## #8 Article view wiring — **READY**

**Size:** L
**Depends on:** #5
**Files:** `Mac/MainWindow/Timeline/WebViewController.swift` (or equivalent — locate during implementation), `Shared/Article Rendering/template.html` (add status indicator markup), new JS file for bridge calls
**ADR:** none (implements PRD F-10 to F-13)

**Description**
Hook the article view to the coordinator. On article open: render original HTML immediately; kick off translation in background; on translation arrival, call JS bridge to update `<h1>` and append `<hr class="translation-separator">` + translated body. Show inline status indicator during translation; show inline error + retry button on failure.

**Acceptance criteria**
- [ ] Article view calls `coordinator.translation(for: title:, bodyHTML:, bodySource:)` after rendering original HTML
- [ ] Status indicator (`<div id="translation-status">`) shows "translating…" while `TranslationStatus.translating`; hides on `.translated`; shows error + retry button on `.failed`
- [ ] JS bridge function `updateTranslation(jsonPayload)` updates `<h1>` and appends translated body
- [ ] JS bridge function `translationRetry()` calls native, which clears cache entry and re-runs translation
- [ ] `bodySource` switches between `feedBody` and `extractedBody` based on whether the article extractor is currently active; switching extractor state triggers a re-translation (extractor off → coordinator called again with `.feedBody`; on → coordinator called with `.extractedBody`)

**Verification:** Manual. Open an English article in English target. Verify the 5 user stories from PRD § "User stories" all behave correctly.

---

## #9 Display mode toggle — **READY**

**Size:** M
**Depends on:** #8
**Files:** `Mac/Article/DisplayModeControl.swift` (new — or wherever toolbar controls live), JS update function in the template

**Description**
Reader control in the article toolbar: segmented control with `translation` / `bilingual` / `original`. Toggling switches the WebView's CSS / DOM without re-fetching the translation.

**Acceptance criteria**
- [ ] Segmented control added to the article toolbar (visible only when translation is enabled for the user)
- [ ] Default mode: `translation`
- [ ] `translation` mode: hide original body, show translated body
- [ ] `bilingual` mode: show original body, separator, translated body
- [ ] `original` mode: hide translated body, show original body
- [ ] Title is always shown in the translated form when translation is available, regardless of mode
- [ ] Toggle does not re-call `coordinator.translation(...)`

---

## #10 Manual QA pass — **READY**

**Size:** M
**Depends on:** all
**Files:** none (process)
**Reference:** PRD § "Acceptance criteria"

**Description**
Walk through the 11-item acceptance checklist from the PRD with a real Mac, real RSS feeds, real network conditions.

**Acceptance criteria (PRD checklist)**
- [ ] Translation disabled → opening any article behaves exactly as before
- [ ] Translation enabled, no LLM key configured → English articles translate via Apple Translation within ~2 seconds
- [ ] Translation enabled, no LLM key configured, body > 1500 chars → still translates via Apple, no error
- [ ] Translation enabled, LLM key configured, body > 1500 chars → translates via LLM, cache hit on second open
- [ ] Translation enabled, LLM key configured but endpoint unreachable → inline failure with retry; original text remains
- [ ] Toggle between `translation` / `bilingual` / `original` updates the view without re-fetching
- [ ] Toggling article extractor off then on re-runs translation using extracted body
- [ ] Switching target language in preferences re-runs translation on next open
- [ ] Killing the app and reopening a translated English article → translation renders immediately from cache
- [ ] Deleting an article in the timeline → its cached translation is also deleted (trigger)
- [ ] Translation disabled in preferences → no background work, no preference pane reload, no error logs

If any item fails, open a follow-up issue with the specific symptom + log excerpt.

---

## Dependencies (DAG)

```
#0 (DONE)
  └─→ #1 (types)
        ├─→ #2 (Apple engine)
        ├─→ #3 (source detection)
        └─→ #4 (OpenAI engine)
              └─→ #5 (coordinator + tests)
                    └─→ #8 (article view wiring)
                          └─→ #9 (display mode toggle)

#1 + #4
  └─→ #6 (preferences UI)
        └─→ #7 (preferences tab registration)

#8 + #9 + #7
  └─→ #10 (manual QA)
```

**Critical path:** #1 → #2 → #5 → #8 → #9 → #10 (six PRs end-to-end).

#3, #4, #6, #7 can run in parallel with the critical path.

## Optional compression

The 11 issues above can be merged into ~6 PRs without losing independence:

1. **PR-1:** #1 + #3 (types + source detection — both pure types, no UI, no network)
2. **PR-2:** #2 (Apple engine)
3. **PR-3:** #4 (OpenAI engine — extends `Secrets`)
4. **PR-4:** #5 (coordinator + 7 unit tests — the meat of the work)
5. **PR-5:** #6 + #7 (preferences UI + toolbar tab)
6. **PR-6:** #8 + #9 (article view wiring + display toggle)
7. **PR-7:** #10 (manual QA — separate, runs before release)

#0 is already merged.
