//
//  TranslationCoordinator.swift
//  NetNewsWire
//
//  The translation orchestration layer. Coordinates settings, cache,
//  source-language detection, and engine selection to fulfill a
//  translation request. The public API is deliberately small:
//
//    - `translation(for:...)` — main entry point
//    - `retry(for:...)` — clear cache entry then re-run
//
//  The coordinator is `Sendable` and does not hold `@MainActor` state.
//  Callers (typically a view controller) are responsible for presenting
//  `TranslationStatus` updates in the UI.
//

import Foundation
import ArticlesDatabase
import Secrets

// MARK: - UserDefaults wrapper for @unchecked Sendable

/// UserDefaults is not formally `Sendable` but is thread-safe in practice.
/// This wrapper lets us capture it in `@Sendable` closures without triggering
/// Swift 6's capture checks.
private struct UnsafeSendableUserDefaults: @unchecked Sendable {
	let value: UserDefaults
	init(_ value: UserDefaults) { self.value = value }
}

// MARK: - TranslationCoordinator

public final class TranslationCoordinator: Sendable {

	// MARK: - Dependencies

	/// All external collaborators are expressed as closures so tests can
	/// run without pulling in `UserDefaults`, `ArticlesDatabase`,
	/// `AppleTranslationEngine`, or `OpenAICompatibleEngine`. The live
	/// factory (`TranslationCoordinator.live(...)`) wires in real versions.
	public struct Dependencies: Sendable {
		public var isEnabled: @Sendable () -> Bool
		public var engineChoice: @Sendable () -> TranslationEngineChoice
		public var targetLanguage: @Sendable () -> String
		public var skipWhenSourceMatchesTarget: @Sendable () -> Bool
		/// Returns `true` when the sample text's dominant language equals `targetLanguage`.
		public var checkSourceMatchesTarget: @Sendable (_ title: String, _ bodyHTML: String, _ targetLanguage: String) -> Bool
		/// Look up a cached translation. Returns `nil` when not found.
		public var fetchCache: @Sendable (_ articleID: String, _ targetLanguage: String, _ bodySource: ArticleTranslation.BodySource) async -> ArticleTranslation?
		/// Persist a translation result.
		public var upsertCache: @Sendable (_ translation: ArticleTranslation) async -> Void
		/// Delete a single cache entry (used by `retry` path).
		public var deleteCache: @Sendable (_ articleID: String, _ targetLanguage: String, _ bodySource: ArticleTranslation.BodySource) async -> Void
		/// Returns `true` when `CredentialsStore` has a non-empty OpenAI key.
		public var hasOpenAIKey: @Sendable () -> Bool
		/// Returns the full OpenAI config when the key is present, `nil` otherwise.
		public var openAIConfig: @Sendable () -> OpenAICompatibleEngine.Config?
		/// Translate using the Apple on-device engine. Throws `TranslationError` on failure.
		public var translateWithApple: @Sendable (_ request: TranslationRequest) async throws -> ArticleTranslation
		/// Translate using the OpenAI-compatible engine. Throws `TranslationError` on failure.
		public var translateWithOpenAI: @Sendable (_ request: TranslationRequest) async throws -> ArticleTranslation

		public init(
			isEnabled: @escaping @Sendable () -> Bool,
			engineChoice: @escaping @Sendable () -> TranslationEngineChoice = { .apple },
			targetLanguage: @escaping @Sendable () -> String,
			skipWhenSourceMatchesTarget: @escaping @Sendable () -> Bool,
			checkSourceMatchesTarget: @escaping @Sendable (_ title: String, _ bodyHTML: String, _ targetLanguage: String) -> Bool,
			fetchCache: @escaping @Sendable (_ articleID: String, _ targetLanguage: String, _ bodySource: ArticleTranslation.BodySource) async -> ArticleTranslation?,
			upsertCache: @escaping @Sendable (_ translation: ArticleTranslation) async -> Void,
			deleteCache: @escaping @Sendable (_ articleID: String, _ targetLanguage: String, _ bodySource: ArticleTranslation.BodySource) async -> Void,
			hasOpenAIKey: @escaping @Sendable () -> Bool,
			openAIConfig: @escaping @Sendable () -> OpenAICompatibleEngine.Config?,
			translateWithApple: @escaping @Sendable (_ request: TranslationRequest) async throws -> ArticleTranslation,
			translateWithOpenAI: @escaping @Sendable (_ request: TranslationRequest) async throws -> ArticleTranslation
		) {
			self.isEnabled = isEnabled
			self.engineChoice = engineChoice
			self.targetLanguage = targetLanguage
			self.skipWhenSourceMatchesTarget = skipWhenSourceMatchesTarget
			self.checkSourceMatchesTarget = checkSourceMatchesTarget
			self.fetchCache = fetchCache
			self.upsertCache = upsertCache
			self.deleteCache = deleteCache
			self.hasOpenAIKey = hasOpenAIKey
			self.openAIConfig = openAIConfig
			self.translateWithApple = translateWithApple
			self.translateWithOpenAI = translateWithOpenAI
		}
	}

	// MARK: - Constants

	/// Body lengths at or above this threshold trigger the LLM engine (when
	/// an API key is configured). Below this threshold Apple Translation is
	/// used regardless of key presence.
	public static let longTextThreshold = 1500

	// MARK: - Init

	private let deps: Dependencies

	public init(deps: Dependencies) {
		self.deps = deps
	}

	// MARK: - Public API

	/// Translates the article if needed, consulting cache, source-language
	/// detection, and engine selection rules. Returns `.skipped` when no
	/// translation is required or `.translated` with the cached or freshly
	/// generated result.
	public func translation(
		for articleID: String,
		title: String,
		bodyHTML: String,
		bodySource: ArticleTranslation.BodySource
	) async -> TranslationResult {
		// 1. Feature disabled?
		guard deps.isEnabled() else {
			return .skipped(.disabled)
		}

		// 2. Determine target language.
		let targetLanguage = deps.targetLanguage()

		// 3. Cache hit?
		if let cached = await deps.fetchCache(articleID, targetLanguage, bodySource) {
			return .translated(cached)
		}

		// 4. Source-language matches target? (skip check)
		if deps.skipWhenSourceMatchesTarget() && deps.checkSourceMatchesTarget(title, bodyHTML, targetLanguage) {
			return .skipped(.sourceMatchesTarget)
		}

		// 5. Choose engine.
		let strippedBodyLength = AppleTranslationEngine.stripHTML(bodyHTML).count
		let useLLM = deps.engineChoice() == .openAICompatible || (strippedBodyLength >= Self.longTextThreshold && deps.hasOpenAIKey())

		let request = TranslationRequest(
			articleID: articleID,
			title: title,
			bodyHTML: bodyHTML,
			targetLanguage: targetLanguage,
			bodySource: bodySource
		)

		let translation: ArticleTranslation
		do {
			if useLLM {
				translation = try await deps.translateWithOpenAI(request)
			} else {
				translation = try await deps.translateWithApple(request)
			}
		} catch let error as TranslationError {
			return .failed(error)
		} catch {
			return .failed(.translationFailed(error.localizedDescription))
		}

		// 6. Cache the result.
		await deps.upsertCache(translation)

		return .translated(translation)
	}

	/// Clears the cache entry for this article/target/body combination and
	/// re-runs translation. Used when the user explicitly retries after a
	/// failure.
	public func retry(
		for articleID: String,
		title: String,
		bodyHTML: String,
		bodySource: ArticleTranslation.BodySource
	) async -> TranslationResult {
		let targetLanguage = deps.targetLanguage()
		await deps.deleteCache(articleID, targetLanguage, bodySource)
		return await translation(for: articleID, title: title, bodyHTML: bodyHTML, bodySource: bodySource)
	}
}

// MARK: - Live factory

extension TranslationCoordinator {

	/// Constants for storing the OpenAI-compatible API key in Keychain.
	/// The key is stored as an "Internet Password" entry with:
	/// - Server: `translationServer`
	/// - Security Domain: `CredentialsType.openAICompatibleAPIKey.rawValue`
	/// - Account (username): `translationUsername`
	/// - Password: the API key
	private static let translationServer = "translation.openai-compatible"
	private static let translationUsername = "api-key"

	/// Real coordinator backed by `ArticlesDatabase`, `UserDefaults`,
	/// `CredentialsManager`, and the two engines. The engines themselves are
	/// constructed fresh on each request so preference changes take effect
	/// immediately without a coordinator rebuild.
	public static func live(
		articlesDatabase: ArticlesDatabase,
		defaults: UserDefaults = .standard
	) -> TranslationCoordinator {
		// UserDefaults is not Sendable in Swift 6 but is documented as
		// thread-safe by Apple. `nonisolated(unsafe)` suppresses the
		// sendability check so the closures can read settings lazily.
		let db = articlesDatabase
		nonisolated(unsafe) let d = defaults

		return TranslationCoordinator(deps: Dependencies(
			isEnabled: { TranslationSettings(defaults: d).isEnabled },
			engineChoice: { TranslationSettings(defaults: d).engine },
			targetLanguage: { TranslationSettings(defaults: d).targetLanguage },
			skipWhenSourceMatchesTarget: { TranslationSettings(defaults: d).skipWhenSourceMatchesTarget },
			checkSourceMatchesTarget: { title, bodyHTML, targetLanguage in
				SourceLanguageInspector.live().sourceMatchesTarget(
					title: title,
					bodyHTML: bodyHTML,
					targetLanguage: targetLanguage
				)
			},
			fetchCache: { articleID, targetLanguage, bodySource in
				await MainActor.run {
					db.fetchTranslation(articleID: articleID, targetLanguage: targetLanguage, bodySource: bodySource)
				}
			},
			upsertCache: { translation in
				await MainActor.run {
					db.upsertTranslation(translation)
				}
			},
			deleteCache: { articleID, targetLanguage, bodySource in
				await MainActor.run {
					db.deleteTranslation(articleID: articleID, targetLanguage: targetLanguage, bodySource: bodySource)
				}
			},
			hasOpenAIKey: {
				guard let creds = try? CredentialsManager.retrieveCredentials(
					type: .openAICompatibleAPIKey,
					server: Self.translationServer,
					username: Self.translationUsername
				) else { return false }
				return !creds.secret.isEmpty
			},
			openAIConfig: {
				guard let creds = try? CredentialsManager.retrieveCredentials(
					type: .openAICompatibleAPIKey,
					server: Self.translationServer,
					username: Self.translationUsername
				), !creds.secret.isEmpty else { return nil }
				let settings = TranslationSettings(defaults: d)
				return OpenAICompatibleEngine.Config(
					baseURL: settings.openAIBaseURL,
					apiKey: creds.secret,
					model: settings.openAIModel
				)
			},
			translateWithApple: { request in
				try await AppleTranslationEngine.live().translate(request)
			},
			translateWithOpenAI: { request in
				let settings = TranslationSettings(defaults: d)
				let apiKey = (try? CredentialsManager.retrieveCredentials(
					type: .openAICompatibleAPIKey,
					server: Self.translationServer,
					username: Self.translationUsername
				))?.secret ?? ""
				let config = OpenAICompatibleEngine.Config(
					baseURL: settings.openAIBaseURL,
					apiKey: apiKey,
					model: settings.openAIModel
				)
				return try await OpenAICompatibleEngine.live(config: config).translate(request)
			}
		))
	}
}
