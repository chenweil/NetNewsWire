//
//  TranslationSettings.swift
//  NetNewsWire
//
//  Read-side wrapper over `UserDefaults` for translation preferences.
//  Write-side is added with the Preferences UI (issue #6).
//

import Foundation

/// User-tunable translation settings. Read-only at this layer; writes are
/// performed by the Preferences UI directly via `UserDefaults`.
///
/// Effectively immutable: all stored properties are `let`, `UserDefaults`
/// is documented thread-safe, and `localeProvider` is invoked only from
/// computed properties on this instance. Marked `@unchecked Sendable` to
/// satisfy Swift 6 strict concurrency for the `shared` singleton.
public final class TranslationSettings: @unchecked Sendable {

	public static let shared = TranslationSettings()

	private let defaults: UserDefaults
	private let localeProvider: () -> Locale

	public init(
		defaults: UserDefaults = .standard,
		localeProvider: @escaping () -> Locale = { Locale.current }
	) {
		self.defaults = defaults
		self.localeProvider = localeProvider
	}

	// MARK: - Storage keys

	private enum Key {
		static let isEnabled = "translation.enabled"
		static let engine = "translation.engine"
		static let targetLanguage = "translation.targetLanguage"
		static let skipWhenSourceMatchesTarget = "translation.skipWhenSourceMatchesTarget"
		static let openAIBaseURL = "translation.openAI.baseURL"
		static let openAIModel = "translation.openAI.model"
	}

	// MARK: - Read

	/// Translation is **off by default** — both for new installs and for users
	/// upgrading from a build that did not have translation. Users opt in via
	/// Preferences → Translation → Enable translation.
	public var isEnabled: Bool {
		defaults.bool(forKey: Key.isEnabled)
	}

	/// Which engine to use. Apple Translation is the default — free, on-device,
	/// no setup. `openAICompatible` is the long-text fallback selected per
	/// request (issue #2 ADR) when the user has configured credentials.
	public var engine: TranslationEngineChoice {
		guard
			let raw = defaults.string(forKey: Key.engine),
			let choice = TranslationEngineChoice(rawValue: raw)
		else {
			return .apple
		}
		return choice
	}

	/// BCP-47 language identifier the user wants translations in.
	///
	/// Falls back to the system locale's language code on first launch so a
	/// user who has never opened Preferences still gets translated articles
	/// (per the issue #1 acceptance: "defaults to
	/// `Locale.current.language.languageCode?.identifier` when unset").
	public var targetLanguage: String {
		if let stored = defaults.string(forKey: Key.targetLanguage), !stored.isEmpty {
			return stored
		}
		return localeProvider().language.languageCode?.identifier ?? "en"
	}

	/// When `true` (default), skip translation if `SourceLanguageInspector`
	/// determines the article is already in the target language. Issue #1 +
	/// PRD F-11.
	public var skipWhenSourceMatchesTarget: Bool {
		if defaults.object(forKey: Key.skipWhenSourceMatchesTarget) == nil {
			return true
		}
		return defaults.bool(forKey: Key.skipWhenSourceMatchesTarget)
	}

	/// OpenAI-compatible base URL for the long-text fallback engine.
	/// Default: `https://api.openai.com/v1/`. Users can override to point at
	/// DeepSeek, OpenRouter, a self-hosted gateway, etc.
	public var openAIBaseURL: URL {
		guard
			let raw = defaults.string(forKey: Key.openAIBaseURL),
			let url = URL(string: raw),
			url.scheme?.hasPrefix("http") == true
		else {
			return URL(string: "https://api.openai.com/v1/")!
		}
		return url
	}

	/// OpenAI-compatible model name. Default: `gpt-4o-mini` (cheap, good for
	/// short translation snippets; users can swap for `gpt-4o`,
	/// `deepseek-chat`, `qwen-plus`, etc.).
	public var openAIModel: String {
		defaults.string(forKey: Key.openAIModel) ?? "gpt-4o-mini"
	}
}

/// Which translation engine the user has selected. Persisted as the raw string
/// in `UserDefaults` so renumbering cases in the future stays safe.
public enum TranslationEngineChoice: String, Sendable, CaseIterable {
	case apple
	case openAICompatible = "openai_compatible"
}
