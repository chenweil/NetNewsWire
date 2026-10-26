# Placeholder Animation Instead of Live Markup While Translating

The translation engines return HTML. While a translation is still arriving, that HTML is incomplete: tags are half-written, and showing it as it streams puts raw markup into the article view — the reader sees `<p><strong>工具：</strong> <a href="…">…</a></p>` instead of an article. A typewriter effect makes this worse, not better: it animates the source code.

So the article view never shows the translation while it is being produced. The `.translating` state renders a shimmering skeleton that stands in for the incoming text, and the finished translation fades in over it through the existing `.translated` rendering. The skeleton is drawn with `currentColor` in `core.css`, so it follows every theme without theme-specific rules, and it does not animate under `prefers-reduced-motion: reduce`.

The stream itself is unchanged: `OpenAICompatibleEngine` still parses SSE deltas and the coordinator still accumulates them, so a stream that fails halfway can show the text it did produce. That partial body is HTML too, so the failure path strips the tags and shows plain text — never markup. The completed translation is rendered as HTML, exactly as before.

The placeholder is a deliberate trade: the reader no longer watches the translation arrive word by word, and instead waits behind an animation. The alternative — rendering the stream as live HTML — would mean injecting model output into the page as it arrives, which is both a sanitizer problem and a source of flicker from half-written tags.
