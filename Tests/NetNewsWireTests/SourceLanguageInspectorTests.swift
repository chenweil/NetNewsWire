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

	@Test func sampleTruncatesBodyToFiveHundredChars() {
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
		// Title (5) + space (1) + first 500 chars of body = 506
		#expect(box.value == 506)
	}

	@Test func sampleStartsWithTitleThenSpaceThenBody() {
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
		#expect(box.value == "Hello World")
	}
}