# Translation

On-demand translation of opened RSS articles from each article's source language into the user's target language. Translation happens only when the article view is opened; the timeline (article list) is never translated. Mac-only.

## Language

**Translation**
: Converting the `title` and `body` of a feed article from its source language into the user's target language, rendered inline in the article view below the original. Never rendered in the timeline.
_Avoid_: Localization (refers to UI strings, not article content); Transcription.

**Target Language**
: The language the user wants articles translated into. Defaults to the system locale on first launch; overridable in Preferences → Translation.
_Avoid_: Output language; Destination language.

**Translation Engine**
: A system that produces a translation. Either `Apple Translation` (on-device) or an `OpenAI-Compatible Engine` (HTTP).
_Avoid_: Translator (overloaded); Backend; Provider.

**Apple Translation Engine**
: The on-device translation engine backed by Apple's `Translation` framework. Free, private (no network), requires no API key. Used as the default engine for all translations.
_Avoid_: System translation; OS translation.

**OpenAI-Compatible Engine**
: An LLM-based translation engine accessed via HTTP, speaking the OpenAI Chat Completions protocol. Configurable `baseURL` + `apiKey` + `model`. Used only as a fallback for long articles when the Apple Translation engine is judged insufficient.
_Avoid_: Cloud translation; GPT translation; LLM translator.

**Long-Text Fallback**
: The rule that routes translations whose source text exceeds the `longTextThreshold` (≥ 1500 characters) to the OpenAI-Compatible engine (when configured) instead of Apple Translation. When no LLM credentials are configured, Apple Translation handles the text regardless of length.
_Avoid_: LLM fallback; Engine switch.

**Translation Cache**
: Persisted translations stored as a `translations` table inside the Articles database. Primary key is `(articleID, targetLanguage, bodySource)`. Survives app restart. Switching target language does not invalidate other languages' entries — it simply misses the cache.
_Avoid_: Translation history; Translation store.

**Body Source**
: Which text was used as translation input. `feedBody` (the RSS feed's `content:encoded` or equivalent) or `extractedBody` (Mercury Parser output, present only when the article extractor is enabled). Translation always follows the body source currently being displayed in the article view; switching the extractor invalidates the cache entry for the affected source.
_Avoid_: Source text; Article content.

**Source Language Detection**
: A check that uses `NLTagger.dominantLanguage` over the first ~500 characters of the article's title and body to decide whether the article is already in the target language. When the dominant language matches the target language, translation is skipped. The full check is gated by a user preference (`Skip translation when source language already matches target language`), default ON.
_Avoid_: Language detection; Language identification.

**Translation Status**
: The lifecycle state of a translation request for one article: `idle` / `translating` / `translated` / `failed(retry)`. Drives the inline status indicator above the body and the retry affordance on failure.
_Avoid_: Translation state.

**Translation Display Mode**
: The reader's choice of how translation and original text coexist in the article view: `translation` (translated only, default), `bilingual` (original first, then `<hr class="translation-separator">`, then translated), `original` (English only). Title is always shown in the translated form when translation is available, regardless of display mode — the toggle affects body only.
_Avoid_: View mode; Reader mode.

**Translation Coordinator**
: The orchestration layer that owns the decision flow: is translation enabled, does the source language match the target, what is the body source, is there a cache hit, which engine should run, did the engine succeed. Returns a `TranslationResult` to the article view; never touches `WKWebView` directly.
_Avoid_: Translation manager; Translation service.
