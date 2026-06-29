# LLM Long-Text Fallback Above 1500 Characters

We route translations of bodies whose extracted or feed text is at least 1500 characters to the OpenAI-compatible LLM engine (when an API key is configured); shorter translations stay on Apple Translation. The 1500-character threshold is set once and lives as a constant in `TranslationCoordinator`.

The reasoning: Apple Translation is good enough for short, factual RSS (news, headlines, technical snippets — the common case in an RSS reader). For long-form content (blog essays, op-eds, literary writing) Apple Translation visibly degrades. Without the fallback, a user reading a long English blog post gets a noticeably worse translation than a user reading a short news blurb. With the fallback, the cost is paid only where it pays for itself.

Why not always-LLM? Cost (~$0.001–$0.005 per article, × dozens per day, × every month). Why not never-LLM? Quality on long-form content. Why not user-controlled threshold? Settings surface bloat — every additional toggle is a decision the user has to make on every article they don't open.

If quality on short articles ever becomes a problem, the right move is to lower the threshold (or remove it) and accept the cost. If cost ever becomes a problem, raise the threshold.
