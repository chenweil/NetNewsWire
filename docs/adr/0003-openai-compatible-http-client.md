# OpenAI-Compatible HTTP Client Instead of a Per-Vendor Client

The LLM fallback uses an HTTP client that speaks the OpenAI Chat Completions protocol with three configurable fields: `baseURL`, `apiKey`, `model`. Default values target `api.openai.com` + `gpt-4o-mini`. Claude (Anthropic) is **not** supported by this client.

A single client covers OpenAI, DeepSeek, OpenRouter, self-hosted gateways, and any local relay (Ollama, LM Studio via OpenAI-compatible shim) — which together account for the vast majority of LLM usage in 2026. The OpenAI Chat Completions protocol is the de facto standard; everyone who is not Anthropic ships a compatible endpoint.

Claude was excluded because its Messages API uses a different request shape, different auth header convention, and different streaming chunk format. Adding Claude would mean a second client implementation (~150 lines), a second credential type in `Secrets`, and a second engine-selection branch in `TranslationCoordinator`. If a future user demand justifies it, add a `ClaudeTranslationEngine` alongside the existing one — the abstraction is already in place.

Why not just hardcode OpenAI? Because DeepSeek and OpenRouter are price/quality-competitive for English→Chinese translation and many users prefer them. Locking the user to one vendor is a one-line decision with a multi-year cost.
