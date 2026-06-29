//
//  SourceLanguageInspector.swift
//  NetNewsWire
//
//  Thin wrapper over `NaturalLanguage.NLTagger.dominantLanguage` that
//  decides whether an article's source language already matches the user's
//  target language (PRD F-11). When it does, `TranslationCoordinator` short-
//  circuits with `TranslationResult.skipped(.sourceMatchesTarget)` so the
//  user sees the original article instead of an "Apple says your article is
//  already in zh-Hans" round-trip.
//
//  Sample strategy: visible body text first, then title. The body window is
//  large enough for NLTagger to make a confident decision on most articles
//  and keeps English titles, product names, and HTML markup from dominating
//  articles that are otherwise already in the target language.
//

import Foundation
import NaturalLanguage

public struct SourceLanguageInspector: Sendable {

	/// (text) -> BCP-47 language identifier, or `nil` if undetermined.
	///
	/// Injected so unit tests can run without depending on NLTagger's
	/// availability heuristics. Production code uses `.live()`.
	private let detect: @Sendable (String) -> String?

	public init(detect: @escaping @Sendable (String) -> String?) {
		self.detect = detect
	}

	/// Detects the dominant language of `text`.
	/// Returns `nil` for empty input or when the underlying tagger is unsure.
	public func dominantLanguage(of text: String) -> String? {
		guard !text.isEmpty else { return nil }
		return detect(text)
	}

	/// `true` when the sampled text's dominant language matches
	/// `targetLanguage` and we can safely skip translation.
	///
	/// `nil` detection (very short input, mixed scripts, etc.) returns
	/// `false` — "we don't know" is treated as "translate anyway".
	public func sourceMatchesTarget(
		title: String,
		bodyHTML: String,
		targetLanguage: String
	) -> Bool {
		let sample = Self.sampleText(title: title, bodyHTML: bodyHTML)
		if Self.visibleTextLooksLikeTargetLanguage(sample, targetLanguage: targetLanguage) {
			return true
		}
		guard let detected = detect(sample) else { return false }
		return Self.languagesMatch(detected, targetLanguage)
	}

	/// Visible body text first, then title. Article bodies are a stronger
	/// signal than titles because RSS titles often contain English product
	/// names even when the article itself is already in the user's language.
	static func sampleText(title: String, bodyHTML: String) -> String {
		let bodyText = AppleTranslationEngine.stripHTML(bodyHTML)
		let head = bodyText.prefix(700) + " " + title
		return String(head)
	}

	private static func languagesMatch(_ detectedLanguage: String, _ targetLanguage: String) -> Bool {
		let detected = Locale.Language(identifier: detectedLanguage).languageCode?.identifier
		let target = Locale.Language(identifier: targetLanguage).languageCode?.identifier
		return detected != nil && detected == target
	}

	private static func visibleTextLooksLikeTargetLanguage(_ text: String, targetLanguage: String) -> Bool {
		guard Locale.Language(identifier: targetLanguage).languageCode?.identifier == "zh" else {
			return false
		}

		let counts = text.reduce(into: ScriptCounts()) { counts, character in
			for scalar in character.unicodeScalars {
				counts.add(scalar)
			}
		}
		let meaningfulCount = counts.cjk + counts.latin + counts.kana + counts.hangul
		guard meaningfulCount >= 80, counts.kana < 5, counts.hangul < 5 else { return false }
		return counts.cjk >= 20 && Double(counts.cjk) / Double(meaningfulCount) >= 0.25
	}

	private struct ScriptCounts {
		var cjk = 0
		var latin = 0
		var kana = 0
		var hangul = 0

		mutating func add(_ scalar: Unicode.Scalar) {
			switch scalar.value {
			case 0x4E00...0x9FFF, 0x3400...0x4DBF:
				cjk += 1
			case 0x0041...0x005A, 0x0061...0x007A:
				latin += 1
			case 0x3040...0x30FF:
				kana += 1
			case 0xAC00...0xD7AF:
				hangul += 1
			default:
				break
			}
		}
	}
}

// MARK: - Production factory

extension SourceLanguageInspector {
	/// Real inspector backed by `NLTagger.dominantLanguage`.
	///
	/// `NLTagger` is generally not thread-safe; we create a fresh instance
	/// per call rather than caching one. The allocation cost is trivial
	/// relative to NLTagger's own model-load cost.
	public static func live() -> SourceLanguageInspector {
		SourceLanguageInspector { text in
			guard !text.isEmpty else { return nil }
			let tagger = NLTagger(tagSchemes: [.language])
			tagger.string = text
			return tagger.dominantLanguage?.rawValue
		}
	}
}
