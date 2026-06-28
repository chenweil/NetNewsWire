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
}
