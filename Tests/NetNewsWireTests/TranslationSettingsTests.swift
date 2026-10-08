//
//  TranslationSettingsTests.swift
//  NetNewsWireTests
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite struct TranslationSettingsTests {

	@Test("isEnabled defaults to false")
	func isEnabledDefaultsToFalse() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.isEnabled == false)
	}

	@Test("engine defaults to apple")
	func engineDefaultsToApple() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.engine == .apple)
	}

	@Test("targetLanguage defaults to system locale language code")
	func targetLanguageDefaultsToSystemLocale() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(
			defaults: defaults,
			localeProvider: { Locale(identifier: "en") }
		)
		#expect(settings.targetLanguage == "en")
	}

	@Test("skipWhenSourceMatchesTarget defaults to true")
	func skipWhenSourceMatchesTargetDefaultsToTrue() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.skipWhenSourceMatchesTarget == true)
	}

	@Test("openAIBaseURL defaults to OpenAI")
	func openAIBaseURLDefaultsToOpenAI() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.openAIBaseURL.absoluteString == "https://api.openai.com/v1/")
	}

	@Test("openAIModel defaults to gpt-4o-mini")
	func openAIModelDefaultsToGpt4oMini() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.openAIModel == "gpt-4o-mini")
	}

	@Test("displayMode defaults to translation")
	func displayModeDefaultsToTranslation() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.displayMode == .translation)
	}

	@Test("displayMode round-trips through defaults")
	func displayModeRoundTripsThroughDefaults() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		let settings = TranslationSettings(defaults: defaults)

		settings.displayMode = .bilingual
		#expect(settings.displayMode == .bilingual)

		settings.displayMode = .original
		#expect(settings.displayMode == .original)

		settings.displayMode = .translation
		#expect(settings.displayMode == .translation)
	}

	@Test("displayMode falls back to translation on invalid stored value")
	func displayModeFallsBackOnInvalidStoredValue() {
		let defaults = UserDefaults(suiteName: "translation-tests-\(UUID().uuidString)")!
		defaults.set("nonsense", forKey: "translation.displayMode")
		let settings = TranslationSettings(defaults: defaults)
		#expect(settings.displayMode == .translation)
	}
}
