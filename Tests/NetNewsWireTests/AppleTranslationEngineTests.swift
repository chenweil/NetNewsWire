//
//  AppleTranslationEngineTests.swift
//  NetNewsWireTests
//
//  Tests for the on-device Apple Translation engine. The translator is
//  injected so the tests run without depending on Apple's framework — the
//  framework glue lives in `AppleTranslationEngine.live()`.
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite struct AppleTranslationEngineTests {

	/// Deterministic translator: tag is appended per paragraph (split by
	/// blank lines) so the test can verify that stripHTML preserved paragraph
	/// structure through the round-trip into the wrap-as-HTML step.
	private func taggingTranslator(tag: String) -> @Sendable (String, String) async throws -> String {
		{ text, target in
			guard !text.isEmpty else { return "" }
			return text
				.components(separatedBy: "\n\n")
				.map { $0.isEmpty ? "" : "\($0)[\(tag):\(target)]" }
				.joined(separator: "\n\n")
		}
	}

	// MARK: - Empty / whitespace

	@Test func emptyInputsProduceEmptyOutput() async throws {
		let engine = AppleTranslationEngine(translateText: self.taggingTranslator(tag: "x"))
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "",
			bodyHTML: "",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.title == "")
		#expect(result.body == "")
	}

	@Test func whitespaceOnlyBodyProducesEmptyBody() async throws {
		let engine = AppleTranslationEngine(translateText: self.taggingTranslator(tag: "x"))
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "Hello",
			bodyHTML: "   \n\n   ",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.title == "Hello[x:zh-Hans]")
		#expect(result.body == "")
	}

	// MARK: - Plain text

	@Test func plainTitleAndBodyAreTranslatedAndWrapped() async throws {
		let engine = AppleTranslationEngine(translateText: self.taggingTranslator(tag: "t"))
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "Hello world",
			bodyHTML: "First sentence. Second sentence.",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.title == "Hello world[t:zh-Hans]")
		#expect(result.body == "<p>First sentence. Second sentence.[t:zh-Hans]</p>")
	}

	// MARK: - HTML stripping

	@Test func paragraphTagsBecomeParagraphs() async throws {
		let engine = AppleTranslationEngine(translateText: self.taggingTranslator(tag: "t"))
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "T",
			bodyHTML: "<p>One.</p><p>Two.</p>",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.body == "<p>One.[t:zh-Hans]</p>\n<p>Two.[t:zh-Hans]</p>")
	}

	@Test func inlineTagsAreStripped() async throws {
		let engine = AppleTranslationEngine(translateText: { text, _ in text })
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "T",
			bodyHTML: "<p>A <strong>bold</strong> and <em>italic</em> word.</p>",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.body == "<p>A bold and italic word.</p>")
	}

	@Test func htmlEntitiesAreDecoded() async throws {
		let engine = AppleTranslationEngine(translateText: { text, _ in text })
		let result = try await engine.translate(TranslationRequest(
			articleID: "abc",
			title: "T",
			bodyHTML: "<p>AT&amp;T &lt;rocks&gt;</p>",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))
		#expect(result.body == "<p>AT&T <rocks></p>")
	}

	// MARK: - Result metadata

	@Test func resultCarriesRequestMetadataAndAppleEngine() async throws {
		let engine = AppleTranslationEngine(translateText: { text, _ in text })
		let request = TranslationRequest(
			articleID: "article-42",
			title: "Title",
			bodyHTML: "<p>Body.</p>",
			targetLanguage: "ja",
			bodySource: .extractedBody
		)
		let result = try await engine.translate(request)
		#expect(result.articleID == "article-42")
		#expect(result.targetLanguage == "ja")
		#expect(result.bodySource == .extractedBody)
		#expect(result.engine == .apple)
		#expect(result.translatedAt.timeIntervalSinceNow > -5)
	}
}