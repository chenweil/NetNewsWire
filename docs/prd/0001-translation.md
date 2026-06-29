# PRD: Article Translation (Mac)

**Status:** Proposed — derived from the design grill of 28-06-2026.
**Scope:** macOS only. iOS out of scope (engine code lives in `Shared/` and is portable later).
**Source docs:** [`Technotes/Translation.markdown`](../../Technotes/Translation.markdown), [`CONTEXT.md`](../../CONTEXT.md), [`docs/adr/0001-…`](../../docs/adr/), [`0002-…`](../../docs/adr/0002-llm-long-text-fallback.md), [`0003-…`](../../docs/adr/0003-openai-compatible-http-client.md).

## Background

NetNewsWire users read RSS in many languages. A common pain: an English article appears in the timeline; the user clicks; the body is in English; the user either skips the article or copies it into a separate translator. Both paths waste attention.

This feature brings translation **into the article view**. The user opens an English article and sees a Chinese version automatically — without leaving NetNewsWire, without copy-pasting, without paying for a separate translation app.

## Goals

1. Translating a freshly-opened English article into the user's target language takes one click (the click that opens the article) — not two.
2. Translation of a previously-opened article is instantaneous (cache hit), even after app restart.
3. The default path costs nothing and sends no article content off-device.
4. The reader can always see the original text alongside the translation, and can revert to original-only with one click.
5. Failure is visible and recoverable (a "retry" affordance), never silent.

## Non-goals

1. Translating the timeline (article list). Translation happens in the article view only.
2. iOS UI for translation. Engine code is in `Shared/` so adding iOS later is additive.
3. Translating feed titles, article summaries, or author names.
4. Per-article target language override. One target language per user.
5. Translating article content already in the target language (skipped by source-language detection).
6. Building a translation server or hosting our own model.

## User stories

1. **Read English news in Chinese.** Wei opens `Hacker News` feed, clicks a story, sees Chinese title and Chinese body in two seconds; can scroll to compare with English at any time.
2. **Read Chinese in English.** Daniel opens `Solidot`, English title and English body appear.
3. **Read long essays better.** Priya opens a 5,000-character essay. After ~2 seconds (LLM round-trip), a higher-quality translation arrives and is cached; reopening is instant.
4. **No surprises.** Karim opens a Chinese article on `Hacker News` — nothing happens, the article is already in his target language.
5. **Recover from failure.** Aiko is offline; the translation shows "translation failed, retry" inline; she clicks retry once she's back online; the translation appears.

## Functional requirements

| # | Requirement |
|---|-------------|
| F-1 | When the user opens an article whose body is in a language other than the user's target language, translate the `title` and `body` automatically. |
| F-2 | Timeline (article list) is **never** translated. |
| F-3 | Translation supports `title` and `body`. `summary`, `authors`, and feed titles are not translated. |
| F-4 | The target language is settable in Preferences → Translation; defaults to the system locale on first launch. |
| F-5 | The default engine is Apple Translation (on-device, free, no API key). |
| F-6 | When the configured body text exceeds 1500 characters AND the user has configured an OpenAI-compatible API key, route the translation to that engine instead. |
| F-7 | When the OpenAI-compatible engine is selected but no API key is configured, fall back to Apple Translation and inform the reader inline. |
| F-8 | Translation results are cached in the Articles database, keyed by `(articleID, targetLanguage, bodySource)`. Reopening an article does not re-translate. |
| F-9 | Switching the article extractor on/off re-runs translation using the new body source. Switching target language does the same. No explicit cache-invalidation code is needed; both are natural cache misses. |
| F-10 | A reader control lets the user toggle between three display modes: `translation` (default), `bilingual` (original + separator + translation), `original` (English only). The toggle affects body only; the translated title is always shown in the header when translation is available. |
| F-11 | If the source language (detected via `NLTagger.dominantLanguage` on the first ~500 characters) matches the target language, skip translation entirely. A user preference (`Skip translation when source language already matches target language`, default ON) gates this behavior. |
| F-12 | When translation is in progress, an inline status indicator is shown above the body (`translating…`). When complete, the indicator disappears. |
| F-13 | On translation failure (network, rate limit, language pack unavailable, credentials missing), an inline error appears with a `retry` button. The original text remains readable in the meantime. |
| F-14 | The OpenAI-compatible engine is configurable: `baseURL` (default `https://api.openai.com/v1`), `apiKey` (stored in Keychain), `model` (default `gpt-4o-mini`). |
| F-15 | Translation is **disabled by default** for new installs and upgrades. Users opt in via Preferences → Translation → Enable translation. |
| F-16 | Apple Translation runs in-process and does not require a privacy disclosure beyond what the OS already shows. OpenAI-compatible engine sends article content to a third-party endpoint and must be reflected in the app's privacy manifest. |
| F-17 | No in-app onboarding. The feature is documented in release notes only. |

## Non-functional requirements

| # | Requirement |
|---|-------------|
| NF-1 | A successful translation (Apple) appears within ~2 seconds for a 1KB article on a modern Mac. A 5KB article finishes within ~5 seconds. |
| NF-2 | Cache lookup is O(1) and adds <10ms to article open. |
| NF-3 | Translation does not block the main thread; the article view shows the original text immediately and replaces/augments when translation arrives. |
| NF-4 | The translation cache grows at most to ~5MB per 1,000 articles. Deleting an article cascades to delete its cached translations. |
| NF-5 | The OpenAI-compatible engine never sends the article's HTML unfiltered — it strips non-content nodes (advertising, tracking pixels) before transmitting. (Tracked separately if/when implemented.) |
| NF-6 | Failed translation never causes the article view to be blank or broken. Original text is the floor of UX. |
| NF-7 | Reopening the same article in the same target language is instantaneous after first successful translation (no engine re-invocation). |

## Architecture summary

Three layers, each with one job:

1. **`Shared/Translation/`** — engine-agnostic logic.
   - `TranslationEngine` protocol (`func translate(_ request:) async throws -> Translation`)
   - `AppleTranslationEngine` (system `Translation` framework)
   - `OpenAICompatibleEngine` (HTTP, OpenAI Chat Completions protocol)
   - `SourceLanguageInspector` (`NLTagger.dominantLanguage`)
   - `TranslationCoordinator` (cache lookup → source detection → engine selection → persist)
2. **`Modules/ArticlesDatabase`** — persistence.
   - `Translation` model
   - `translations` table, keyed `(articleID, targetLanguage, bodySource)`
   - Trigger to delete translations on article delete
3. **`Mac/`** — UI integration.
   - `Preferences/Translation/TranslationPreferencesViewController` (new preferences tab)
   - `MainWindow/.../WebViewController` calls coordinator; appends translation via JS bridge

The coordinator is the only place where decisions happen. Engines are interchangeable. The persistence layer is unaware of engines.

## Decisions of record

Non-obvious decisions, each in its own ADR:

- [Apple Translation as primary engine](../adr/0001-apple-translation-as-primary-engine.md) — Apple first, LLM only as fallback. Reverses the "AI API" intuition.
- [LLM long-text fallback above 1500 characters](../adr/0002-llm-long-text-fallback.md) — short articles stay free and on-device; long articles opt into the LLM.
- [OpenAI-compatible HTTP client instead of a per-vendor client](../adr/0003-openai-compatible-http-client.md) — one client covers OpenAI, DeepSeek, OpenRouter, self-hosted, local. Claude excluded by protocol mismatch.

Domain vocabulary: [`CONTEXT.md`](../../CONTEXT.md) — 12 terms.

## Acceptance criteria

Before each release touching translation:

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

Unit tests (per the test plan in [`Technotes/Translation.markdown`](../../Technotes/Translation.markdown) § "Decision index" row 17): 7 cases on `TranslationCoordinator`.

## Future work (deliberately out of scope)

- iOS UI for translation. Engine code in `Shared/` is portable.
- Per-article target language override.
- Translation of `summary` and `authors` fields.
- Batch pre-translation of a feed (e.g., "translate all unread of this feed") — would need rate limiting and a queue; revisit if users request.
- Translation of feed titles (would affect timeline rendering).
- Server-side translation (no current justification).
