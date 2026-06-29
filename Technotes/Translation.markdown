# Translation

NetNewsWire can translate the `title` and `body` of an article into the user's target language when the article is opened. The timeline is **never** translated. Mac only.

This document captures scope and behavior. Domain vocabulary lives in [`../CONTEXT.md`](../CONTEXT.md). Non-obvious decisions live in [`../docs/adr/`](../docs/adr/).

## Behavior summary

1. The user opens an article.
2. If translation is enabled and the article's source language is not the user's target language, NetNewsWire translates the title and body.
3. The translation appears below the original, separated by a thin rule. The reader can toggle between `translation` (default), `bilingual`, and `original` via a segmented control.
4. The title is translated once; the body is translated once. Subsequent openings of the same article in the same target language come from a cache persisted in the Articles database.
5. Translation failures (network, rate limit, missing language pack) are surfaced inline with a retry affordance; the original text remains readable.

## Engines

Two engines are available, selected automatically:

- **Apple Translation** (default). On-device via the system `Translation` framework. Free, no API key, no network round-trip.
- **OpenAI-Compatible** (long-text fallback). HTTP client speaking the OpenAI Chat Completions protocol; configurable `baseURL`, `apiKey`, `model`. Used only when the body text is ≥ 1500 characters AND the user has configured credentials.

If the OpenAI-compatible engine is selected but no API key is configured, Apple Translation handles the text and an inline note informs the reader.

## Decision index

| #  | Decision                                              | Rationale                                       |
|----|-------------------------------------------------------|-------------------------------------------------|
| 1  | Translate `title` + `body` on opening; not in list    | Pain point is in the detail view, not the list |
| 2  | Smart auto-translate + reader toggle (译文 / 对照 / 原文) | Removes per-article click friction             |
| 3  | Target language = system locale default, app override | First-launch defaults to system; user can pin   |
| 4  | Apple Translation first; LLM added later              | Free, private, no setup for most users           |
| 5  | Apple default; LLM as long-text fallback              | Quality matters most on long-form content       |
| 6  | OpenAI-compatible HTTP client                         | One client covers OpenAI/DeepSeek/OpenRouter/local |
| 7  | Cache persisted in Articles DB keyed by `(articleID, targetLanguage, bodySource)` | Restart-safe; target-language switch is lookup miss |
| 8  | Source detection via `NLTagger` (first ~500 chars) + user-toggleable skip | Avoid translating when source already matches target |
| 9  | Translation body source follows the displayed body source | No "I see more than I read" tearing              |
| 10 | Single `WKWebView`; translation appended below `<hr>` | Avoids scroll-sync rabbit holes                  |
| 11 | Inline status indicator + retry on failure            | Success path stays clean; failure path has affordance |
| 12 | Mac only; iOS out of scope                            | User scope decision                              |
| 13 | LLM preferences: `apiKey` + `baseURL` + `model`       | Covers OpenAI/DeepSeek/OpenRouter; no advanced knobs |
| 14 | Translation logic lives in `Shared/Translation/`; not in `ArticleRenderer` | `ArticleRenderer` stays a pure function         |
| 15 | New Preferences → Translation tab                     | Five+ settings need their own surface            |
| 16 | No in-app onboarding; release notes only              | Project tradition (see existing release notes)  |
| 17 | Unit tests for `TranslationCoordinator` only          | Branches and cache invariants; the rest is manual QA |

## Architectural decisions

Three decisions are non-obvious enough to warrant their own records:

- [Apple Translation as Primary Engine](../docs/adr/0001-apple-translation-as-primary-engine.md)
- [LLM Long-Text Fallback Above 1500 Characters](../docs/adr/0002-llm-long-text-fallback.md)
- [OpenAI-Compatible HTTP Client Instead of a Per-Vendor Client](../docs/adr/0003-openai-compatible-http-client.md)

## Manual QA checklist

Before each release with translation changes, verify by hand:

- [ ] Translation disabled → opening any article behaves exactly as before
- [ ] Translation enabled, no LLM key configured → English articles translate via Apple Translation within seconds
- [ ] Translation enabled, no LLM key configured, body > 1500 chars → still translates via Apple, no error
- [ ] Translation enabled, LLM key configured, body > 1500 chars → translates via LLM, cache hit on second open
- [ ] Translation enabled, LLM key configured but endpoint unreachable → inline failure with retry; original text remains
- [ ] Toggle between `translation` / `bilingual` / `original` updates the view without re-fetching
- [ ] Toggling article extractor off then on re-runs translation using extracted body
- [ ] Switching target language in preferences re-runs translation on next open
- [ ] Kill app, reopen same English article → translation renders immediately from cache

## Out of scope (deliberately)

- Translating article summaries (`summary` field) — usually duplicates body in modern feeds
- Translating the timeline / article list — explicitly excluded by design
- Per-article target language override — settings tab is enough
- Translating feed titles — feed titles are user-facing metadata, not article content
- iOS UI for translation — scope decision; engine code lives in `Shared/` and is portable if iOS is added later
