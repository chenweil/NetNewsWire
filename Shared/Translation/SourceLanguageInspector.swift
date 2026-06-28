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
//  Sample strategy: title + first 500 chars of body. The 500-char window is
//  large enough for NLTagger to make a confident decision on most articles
//  and small enough that the inspector's allocation cost is bounded on
//  multi-thousand-word pieces.
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

	/// `true` when the sampled text's dominant language equals
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
		guard let detected = detect(sample) else { return false }
		return detected == targetLanguage
	}

	/// `title` + space + first 500 chars of `bodyHTML`. The body is passed
	/// through as-is — HTML tags are noise but NLTagger is robust enough on
	/// the typical English/Chinese/Latin article that this still works. If
	/// precision becomes an issue, the caller can strip HTML before calling.
	static func sampleText(title: String, bodyHTML: String) -> String {
		let head = title + " " + bodyHTML.prefix(500)
		return String(head)
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