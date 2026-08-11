//
//  TranslationEngine.swift
//  NetNewsWire
//
//  Engine-agnostic types for the translation feature. Concrete engines
//  (`AppleTranslationEngine`, `OpenAICompatibleEngine`) live in their own
//  files; the coordinator lives in `TranslationCoordinator.swift`.
//
//  The bare name `Translation` is deliberately reserved for these types —
//  the system `Translation` framework on macOS (Apple's on-device
//  translation framework, transplanted from iOS) and the cached record
//  `ArticleTranslation` in `ArticlesDatabase` both lay claim to it.
//

import Foundation
import ArticlesDatabase

// MARK: - Request

/// Inputs to a translation engine. The caller (typically the article view
/// controller) supplies the body HTML and `bodySource` it is currently
/// displaying, so the engine translates what the reader will actually see.
public struct TranslationRequest: Sendable {
	public let articleID: String
	/// Article title as the reader sees it (may have been edited by the
	/// `ArticleRenderer`'s sanitization).
	public let title: String
	/// Article body HTML. Already chosen between feed body and Mercury-
	/// extracted body by the caller, so the engine does not need to know
	/// which is which — it just translates text.
	public let bodyHTML: String
	/// BCP-47 target language identifier, e.g. `zh-Hans`, `en`, `ja`.
	public let targetLanguage: String
	/// Which body source this is. Persisted in the translation cache so
	/// switching the article extractor on/off produces a natural cache miss
	/// instead of a stale read.
	public let bodySource: ArticleTranslation.BodySource

	public init(
		articleID: String,
		title: String,
		bodyHTML: String,
		targetLanguage: String,
		bodySource: ArticleTranslation.BodySource
	) {
		self.articleID = articleID
		self.title = title
		self.bodyHTML = bodyHTML
		self.targetLanguage = targetLanguage
		self.bodySource = bodySource
	}
}

// MARK: - Engine

/// A translation engine. Implementations: `AppleTranslationEngine` (on-device,
/// free, default) and `OpenAICompatibleEngine` (HTTP, long-text fallback).
public protocol TranslationEngine: Sendable {
	func translate(_ request: TranslationRequest) async throws -> ArticleTranslation
}

// MARK: - Result

/// Outcome of a translation attempt, as returned by `TranslationCoordinator`.
/// Distinct from `TranslationStatus` (which is the UI's view of an in-flight
/// or completed translation): `TranslationResult` is the terminal result.
public enum TranslationResult: Sendable, Equatable {
	case translated(ArticleTranslation)
	case skipped(SkipReason)
	case failed(TranslationError)
}

/// Why a translation was not attempted.
public enum SkipReason: Sendable, Equatable {
	/// User has not enabled translation in Preferences → Translation.
	case disabled
	/// Source language already matches the target language (issue #1 + PRD F-11).
	/// Surfaced as `skipped` rather than `translated` so the UI can
	/// distinguish "no work to do" from "we did the work and got this back".
	case sourceMatchesTarget
}

// MARK: - Error

public enum TranslationError: LocalizedError, Sendable, Equatable {
	/// Network is unreachable. Retrying may succeed.
	case networkUnavailable
	/// The translation provider did not return a response before the client timeout.
	case requestTimedOut
	/// User selected the OpenAI-compatible engine but no API key is stored.
	/// Distinct from `failed` so the UI can prompt for credentials.
	case credentialsMissing
	/// HTTP 429 from the LLM provider. Back off and retry.
	case rateLimited
	/// HTTP non-2xx, malformed JSON, or empty body. Treat as transient.
	case invalidResponse
	/// Engine-specific failure with a human-readable detail.
	case translationFailed(String)
	/// Apple Translation cannot download the language pack required for the
	/// target language (no network, OS refusal, etc.).
	case languagePackUnavailable(String)

	public var errorDescription: String? {
		switch self {
		case .networkUnavailable:
			return NSLocalizedString("Network unavailable.", comment: "Translation error")
		case .requestTimedOut:
			return NSLocalizedString("Translation request timed out.", comment: "Translation error")
		case .credentialsMissing:
			return NSLocalizedString("Translation credentials are missing.", comment: "Translation error")
		case .rateLimited:
			return NSLocalizedString("Translation service rate limited the request.", comment: "Translation error")
		case .invalidResponse:
			return NSLocalizedString("Translation service returned an invalid response.", comment: "Translation error")
		case .translationFailed(let message):
			return message
		case .languagePackUnavailable(let message):
			return message
		}
	}
}

// MARK: - Status

/// Lifecycle state of a single translation request, surfaced to the inline
/// status indicator above the body (PRD F-12, F-13).
public enum TranslationStatus: Sendable, Equatable {
	case idle
	case translating
	case translated(ArticleTranslation)
	case failed(String)
	/// Streaming produced visible content before the request failed. The
	/// partial body is intentionally kept out of the translation cache.
	case streamingFailed(String, partialBody: String)
}
