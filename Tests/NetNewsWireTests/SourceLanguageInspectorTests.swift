//
//  SourceLanguageInspectorTests.swift
//  NetNewsWireTests
//
//  Tests for the NLTagger wrapper that detects the source language of
//  an article's body so the coordinator can skip translation when the
//  article is already in the target language (PRD F-11).
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite struct SourceLanguageInspectorTests {

	// MARK: - dominantLanguage

	@Test func emptyTextReturnsNil() {
		let inspector = SourceLanguageInspector(detect: { _ in nil })
		#expect(inspector.dominantLanguage(of: "") == nil)
	}

	@Test func detectClosureReceivesTextAndReturnsValue() {
		final class Box: @unchecked Sendable { var value: String? }
		let box = Box()
		let inspector = SourceLanguageInspector(detect: { text in
			box.value = text
			return "en"
		})
		let result = inspector.dominantLanguage(of: "Hello world")
		#expect(result == "en")
		#expect(box.value == "Hello world")
	}

	// MARK: - sourceMatchesTarget

	@Test func englishSampleWithEnglishTargetSkips() {
		let inspector = SourceLanguageInspector(detect: { _ in "en" })
		let skip = inspector.sourceMatchesTarget(
			title: "Hello",
			bodyHTML: "An English article.",
			targetLanguage: "en"
		)
		#expect(skip == true)
	}

	@Test func englishSampleWithChineseTargetDoesNotSkip() {
		let inspector = SourceLanguageInspector(detect: { _ in "en" })
		let skip = inspector.sourceMatchesTarget(
			title: "Hello",
			bodyHTML: "An English article.",
			targetLanguage: "zh-Hans"
		)
		#expect(skip == false)
	}

	@Test func chineseSampleWithChineseTargetSkips() {
		let inspector = SourceLanguageInspector(detect: { _ in "zh-Hans" })
		let skip = inspector.sourceMatchesTarget(
			title: "标题",
			bodyHTML: "<p>一段中文。</p>",
			targetLanguage: "zh-Hans"
		)
		#expect(skip == true)
	}

	@Test func simplifiedChineseDetectionMatchesGenericChineseTarget() {
		let inspector = SourceLanguageInspector(detect: { _ in "zh-Hans" })
		let skip = inspector.sourceMatchesTarget(
			title: "标题",
			bodyHTML: "<p>一段中文。</p>",
			targetLanguage: "zh"
		)
		#expect(skip == true)
	}

	@Test func chineseBodyWithEnglishTitleSkipsForChineseTarget() {
		let inspector = SourceLanguageInspector(detect: { _ in "en" })
		let body = String(repeating: "这是中文正文，包含 API token Swift OpenAI 这样的英文词，但整体仍然是中文。", count: 4)
		let skip = inspector.sourceMatchesTarget(
			title: "OpenAI Releases GPT-5",
			bodyHTML: "<p>\(body)</p>",
			targetLanguage: "zh-Hans"
		)
		#expect(skip == true)
	}

	@Test func nilDetectionDoesNotSkip() {
		// NLTagger can return nil on very short or non-textual input — treat
		// that as "we don't know, so don't skip and translate anyway".
		let inspector = SourceLanguageInspector(detect: { _ in nil })
		let skip = inspector.sourceMatchesTarget(
			title: "T",
			bodyHTML: "<p>x</p>",
			targetLanguage: "en"
		)
		#expect(skip == false)
	}

	@Test func sampleTruncatesVisibleBodyToSevenHundredChars() {
		final class Box: @unchecked Sendable { var value = 0 }
		let box = Box()
		let longBody = String(repeating: "a", count: 5_000)
		let inspector = SourceLanguageInspector(detect: { text in
			box.value = text.count
			return "en"
		})
		_ = inspector.sourceMatchesTarget(
			title: "Title",
			bodyHTML: longBody,
			targetLanguage: "en"
		)
		// First 700 chars of body + space + Title (5) = 706
		#expect(box.value == 706)
	}

	@Test func sampleStartsWithBodyThenSpaceThenTitle() {
		final class Box: @unchecked Sendable { var value: String? }
		let box = Box()
		let inspector = SourceLanguageInspector(detect: { text in
			box.value = text
			return "en"
		})
		_ = inspector.sourceMatchesTarget(
			title: "Hello",
			bodyHTML: "World",
			targetLanguage: "en"
		)
		#expect(box.value == "World Hello")
	}

	@Test func sampleStripsHTMLBeforeDetection() {
		final class Box: @unchecked Sendable { var value: String? }
		let box = Box()
		let inspector = SourceLanguageInspector(detect: { text in
			box.value = text
			return "en"
		})
		_ = inspector.sourceMatchesTarget(
			title: "Title",
			bodyHTML: "<p>Hello &amp; goodbye.</p>",
			targetLanguage: "en"
		)
		#expect(box.value == "Hello & goodbye. Title")
	}
}
