# Streaming Translation for OpenAI-Compatible Body

Long OpenAI-compatible translations should stream the article body into the detail view instead of waiting for the full response. The title remains a normal request, streamed chunks are displayed as safe text while the original article stays readable, and the completed response is rendered through the existing translated state and cache. Partial streamed output is not cached; if streaming is unsupported, the app falls back to the existing non-streaming request.

The streaming API stays narrow: `OpenAICompatibleEngine` parses standard OpenAI-style SSE (`data:` lines, `[DONE]`, `choices[0].delta.content`) and reports only string deltas through `TranslationCoordinator`. `DetailWebViewController` appends deltas as text nodes via JavaScript, then switches to the existing `.translated` rendering when the complete translation is available. Fallback to non-streaming happens only before any streamed body chunk has been displayed.
