# Apple Translation as Primary Engine

We chose Apple's on-device `Translation` framework as the default translation engine for all article translations. The OpenAI-compatible HTTP engine is added as a long-text fallback only when the user explicitly configures an API key.

The user request was framed as "integrate an AI API". Without this context, a reader of the code would assume an LLM is doing the work and wonder why API-key plumbing, HTTP error handling, and Secrets integration exist at all. The answer: LLM is the **fallback**, not the default. Apple Translation covers the common case (short English RSS — news, blogs, technical posts) at zero cost, zero network, and zero credential setup. Routing everything through an LLM would have added recurring cost, a new secret surface, and a new privacy disclosure for content the user already owns locally.

This is reversible in the sense that the engine selection lives in one place (`TranslationCoordinator`), but it is not free: it constrains the data model (`engine` field on cached translations), the preferences UI, and the failure-recovery path. Worth recording.
