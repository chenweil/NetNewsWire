//
//  AppleTranslationEngine.swift
//  NetNewsWire
//
//  Translation engine backed by Apple's on-device Translation framework
//  (macOS 14.4+). Zero API cost, no key, runs entirely on-device.
//
//  HTML handling: the framework translates plain text only. The engine
//  strips HTML tags (preserving paragraph breaks), translates the stripped
//  text, then re-wraps each non-empty paragraph in `<p>` tags. This is a
//  pragmatic MVP — inline formatting (`<strong>`, `<em>`, links) is lost.
//  Preserving it would require an HTML parser and per-block translation,
//  which is not worth the complexity for v1.
//

import Foundation
import Translation
import ArticlesDatabase

/// Translates text via Apple's on-device Translation framework.
///
/// The actual framework call is wrapped behind `translateText` so unit tests
/// can run without depending on the Translation framework's download/
/// availability state. Production code uses `AppleTranslationEngine.live()`.
public final class AppleTranslationEngine: TranslationEngine, Sendable {

	/// Translates a single string from the engine's default source language
	/// to `targetLanguage` (BCP-47). May throw if the language pack is not
	/// available, network is unavailable, or the framework fails.
	private let translateText: @Sendable (String, String) async throws -> String

	public init(translateText: @escaping @Sendable (String, String) async throws -> String) {
		self.translateText = translateText
	}

	public func translate(_ request: TranslationRequest) async throws -> ArticleTranslation {
		let strippedTitle = Self.stripHTML(request.title)
		let strippedBody = Self.stripHTML(request.bodyHTML)

		// Empty inputs short-circuit to avoid the framework refusing on empty strings.
		let translatedTitle = strippedTitle.isEmpty
			? ""
			: try await translateText(strippedTitle, request.targetLanguage)
		let translatedBodyText = strippedBody.isEmpty
			? ""
			: try await translateText(strippedBody, request.targetLanguage)
		let wrappedBody = Self.wrapAsHTML(translatedBodyText)

		return ArticleTranslation(
			articleID: request.articleID,
			targetLanguage: request.targetLanguage,
			bodySource: request.bodySource,
			title: translatedTitle,
			body: wrappedBody,
			engine: .apple,
			translatedAt: Date()
		)
	}

	// MARK: - HTML helpers

	/// Strip HTML tags and decode a fixed set of entities. Block-level
	/// closing tags become double newlines so paragraph structure survives
	/// the round-trip through plain text.
	static func stripHTML(_ html: String) -> String {
		var result = html
		let blockClosers = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>", "</blockquote>"]
		for tag in blockClosers {
			result = result.replacingOccurrences(of: tag, with: "\n\n", options: .caseInsensitive)
		}
		let lineBreaks = ["<br>", "<br/>", "<br />"]
		for tag in lineBreaks {
			result = result.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
		}
		result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
		let entities: [(String, String)] = [
			("&nbsp;", " "),
			("&amp;", "&"),
			("&lt;", "<"),
			("&gt;", ">"),
			("&quot;", "\""),
			("&apos;", "'"),
			("&#39;", "'"),
		]
		for (entity, replacement) in entities {
			result = result.replacingOccurrences(of: entity, with: replacement)
		}
		result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
		result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Wrap each non-empty paragraph (separated by blank lines) in `<p>` tags.
	/// Empty input returns empty string — no stray empty `<p></p>`.
	static func wrapAsHTML(_ text: String) -> String {
		let paragraphs = text
			.components(separatedBy: "\n\n")
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		guard !paragraphs.isEmpty else { return "" }
		return paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
	}
}

// MARK: - Production factory

extension AppleTranslationEngine {
	/// Real engine backed by Apple's TranslationSession. Each call creates a
	/// fresh session targeting the request's target language.
	///
	/// `TranslationSession` is `@available(macOS 15.0, ...)`, but as of the
	/// Xcode 26 SDK the only public initializer is `init(installedSource:target:)`,
	/// which is gated to macOS 26+. On macOS 15–25 the closure throws — those
	/// OSes have Apple's translation framework but the SDK no longer exposes a
	/// way to construct a session. This will resolve when Xcode ships a
	/// backwards-compatible init or the deployment target moves to macOS 26.
	public static func live() -> AppleTranslationEngine {
		AppleTranslationEngine { text, targetLanguage in
			guard !text.isEmpty else { return "" }
			if #available(macOS 26.0, *) {
				let source = Locale.Language(identifier: "en")
				let target = Locale.Language(identifier: targetLanguage)
				let session = TranslationSession(installedSource: source, target: target)
				let response = try await session.translate(text)
				return response.targetText
			} else {
				throw TranslationError.languagePackUnavailable("Apple Translation requires macOS 26.0+ on this SDK")
			}
		}
	}
}