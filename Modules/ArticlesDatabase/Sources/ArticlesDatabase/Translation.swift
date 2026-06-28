//
//  Translation.swift
//  ArticlesDatabase
//
//  Cached translation of an article's title and body, keyed by
// (articleID, targetLanguage, bodySource) so target-language switching and
// extractor on/off both produce natural cache misses without explicit
// invalidation.
//

import Foundation

/// A persisted translation of one article into one target language.
///
/// Named `ArticleTranslation` (not `Translation`) to avoid colliding with
/// the system `Translation` framework on macOS — Apple's on-device
/// translation framework, transplanted from iOS, exports types under the
/// `Translation` namespace. A name collision in the importer would force
/// every reference to be fully module-qualified.
///
/// `bodySource` distinguishes translations of the feed-provided body from
/// translations of Mercury-extracted body — switching the article extractor
/// off should not silently re-use the old translation.
public struct ArticleTranslation: Sendable, Hashable {

	/// Which text the translation was produced from.
	///
	/// Stored as a string in the database so adding a new source later
	/// (e.g., `readability`) is a migration, not a schema redesign.
	public enum BodySource: String, Sendable, CaseIterable {
		case feedBody
		case extractedBody
	}

	/// Which engine produced the translation.
	///
	/// Recorded for diagnostics and so the UI can show "translated by Apple"
	/// or "translated by OpenAI-compatible" on demand. Adding a new engine
	/// is a code change, not a schema change.
	public enum Engine: String, Sendable {
		case apple
		case openAICompatible = "openai_compatible"
	}

	public let articleID: String
	/// BCP-47 language identifier (e.g., `zh-Hans`, `en`, `ja`).
	public let targetLanguage: String
	public let bodySource: BodySource
	public let title: String
	/// Translated body in HTML, sanitized; the same shape as `article.contentHTML`.
	public let body: String
	public let engine: Engine
	public let translatedAt: Date

	public init(
		articleID: String,
		targetLanguage: String,
		bodySource: BodySource,
		title: String,
		body: String,
		engine: Engine,
		translatedAt: Date
	) {
		self.articleID = articleID
		self.targetLanguage = targetLanguage
		self.bodySource = bodySource
		self.title = title
		self.body = body
		self.engine = engine
		self.translatedAt = translatedAt
	}
}
