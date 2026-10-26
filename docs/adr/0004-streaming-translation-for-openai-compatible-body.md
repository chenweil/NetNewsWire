# Streaming Translation for OpenAI-Compatible Body

Long OpenAI-compatible translations should stream the article body instead of waiting for the full response. The title remains a normal request, the original article stays readable while the translation is produced, and the completed response is rendered through the existing translated state and cache. Partial streamed output is not cached; if streaming is unsupported, the app falls back to the existing non-streaming request.

The streaming API stays narrow: `OpenAICompatibleEngine` parses standard OpenAI-style SSE (`data:` lines, `[DONE]`, `choices[0].delta.content`) and reports only string deltas through `TranslationCoordinator`. `DetailWebViewController` accumulates the deltas, then switches to the existing `.translated` rendering when the complete translation is available. Fallback to non-streaming happens only before any streamed body chunk has been displayed.

The deltas are not rendered into the article view: the engine returns HTML, and a partial translation is not valid HTML yet. The article view shows a placeholder animation while the translation is produced — see [Placeholder Animation Instead of Live Markup While Translating](0005-placeholder-animation-instead-of-live-markup.md). The accumulated body is kept so that a failed stream can show the text it did produce, with the tags stripped.
