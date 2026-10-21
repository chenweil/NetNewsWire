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

**Streaming Translation**
: Progressive display of an OpenAI-Compatible Engine body translation as chunks arrive, before the complete translation is ready. The original article remains readable while the streamed translation is incomplete.
_Avoid_: Streaming response; Token stream; Live rendering.

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
: The lifecycle state of a translation request for one article: `idle` / `translating` / `translated` / `failed(retry)` / `skipped(reason)`. Drives the inline status indicator above the body and the retry affordance on failure. `skipped` carries the reason — `disabled` or `sourceMatchesTarget` — so the article view can say *why* there is no translation instead of silently showing the original.
_Avoid_: Translation state.

**Translation Display Mode**
: The reader's choice of how translation and original text coexist in the article view: `translation` (translated only, default), `bilingual` (original first, then `<hr class="translation-separator">`, then translated), `original` (English only). Title is always shown in the translated form when translation is available, regardless of display mode — the toggle affects body only. The mode is applied when the HTML is rendered, so it works even when article JavaScript is disabled; the toolbar control is disabled while the open article has no translation, because there is nothing for it to switch between, and the mode can be set in Preferences → Translation instead.
_Avoid_: View mode; Reader mode.

**Translation Coordinator**
: The orchestration layer that owns the decision flow: is translation enabled, does the source language match the target, what is the body source, is there a cache hit, which engine should run, did the engine succeed. Returns a `TranslationResult` to the article view; never touches `WKWebView` directly. `localSkipReason(for:bodyHTML:)` answers the same "would this be skipped?" question without a cache lookup, a network request, or an engine call.
_Avoid_: Translation manager; Translation service.

# Comments

The comment thread that belongs to an article, shown below the article body in the article view. A thread is fetched from the site that published the article, because feeds usually carry only the first post of a discussion.

## Language

**Comment Thread**
: The comments attached to an article, in the order the site published them, each with an author, a body, and — when the site provides it — a date and a permalink. The thread is laid out like a transcript: a numbered gutter carries the position of every comment, and the thread keeps its own type scale so it reads as an appendix to the article rather than as more article.
_Avoid_: Replies (a site-specific term); Feedback.

**Comment Ordinal**
: The position of a comment in its thread, counted from one in the order the comments are shown, including replies. It is rendered in a monospaced gutter and links to the comment on the original site.
_Avoid_: Comment number; Comment ID (the site's own identifier is different); Floor (a site-specific term).

**Comments Provider**
: A source of comment threads. A provider declares whether it can serve a given article URL (`canProvideComments(for:)`) and fetches the thread when it can (`fetchComments(for:)`). Adding support for a new site means adding one provider and registering it — the article view does not change.
_Avoid_: Comments source; Comment plugin.

**Comments Service**
: The layer that picks the first provider that claims an article URL and fetches the thread through it, caching threads for the session. It never downloads the original page on its own: a URL that no provider claims produces no comments and no network request.
_Avoid_: Comments manager; Comment loader.

**Topic**
: A discussion on a forum. A V2EX topic is identified by the `/t/<id>` path of its URL; the replies to a topic are its comments.
_Avoid_: Thread (a NetNewsWire term for a column of the timeline); Post.

**Comment Body**
: The HTML of a single comment, as published by the site, with scripts, inline event handlers, and `javascript:` URLs removed before it reaches the article view.
_Avoid_: Comment text; Comment content.

# About

The panel that says who this build of the app is and where to find it. The panel names two different parties, and keeping them apart is the point: the project this app is based on, and the person who made this particular build.

## Language

**Version Author**
: The person responsible for this build of the app, as named in the app bundle (`NNWVersionAuthor`) together with the web address that leads to their work (`NNWVersionAuthorURL`). The About window shows the version author in the copyright line, links their name to their address, and uses that address for the prominent link under the version number.
_Avoid_: Developer; Owner; Maintainer (a role in the upstream project, not in this build).

**Upstream Project**
: The open-source project this app is based on, and the party whose copyright statement the license requires this build to keep. Its author is credited in the copyright line and in the credits list, and its website is the fallback link when the bundle names no version author.
_Avoid_: Original author; Source project.
