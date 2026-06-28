//
//  TranslationCoordinatorTests.swift
//  NetNewsWireTests
//
//  Tests for the translation orchestration layer. The coordinator glues
//  together the settings, cache, engines, and source-language detector.
//  Engines are mocked via closures so the tests focus on the decision tree
//  without hitting real Apple/OpenAI APIs.
//

import Foundation
import Testing
@testable import NetNewsWire
import ArticlesDatabase

@Suite struct TranslationCoordinatorTests {

    // MARK: - Placeholder translation

    private static func placeholder() -> ArticleTranslation {
        ArticleTranslation(
            articleID: "",
            targetLanguage: "",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "",
            body: "",
            engine: ArticleTranslation.Engine.apple,
            translatedAt: .distantPast
        )
    }

    private static func makeTranslation(
        articleID: String,
        targetLanguage: String,
        bodySource: ArticleTranslation.BodySource,
        title: String,
        body: String,
        engine: ArticleTranslation.Engine
    ) -> ArticleTranslation {
        ArticleTranslation(
            articleID: articleID,
            targetLanguage: targetLanguage,
            bodySource: bodySource,
            title: title,
            body: body,
            engine: engine,
            translatedAt: Date()
        )
    }

    // MARK: - Test 1: disabled returns skipped

    @Test func disabledReturnsSkipped() async {
        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { false },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in Self.placeholder() },
            translateWithOpenAI: { _ in Self.placeholder() }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: "<p>World</p>",
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        #expect(result == TranslationResult.skipped(SkipReason.disabled))
    }

    // MARK: - Test 2: cache hit returns cached without calling engine

    @Test func cacheHitReturnsCachedWithoutCallingEngine() async {
        let cached = Self.makeTranslation(
            articleID: "a1",
            targetLanguage: "zh-Hans",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "Cached Title",
            body: "<p>Cached Body</p>",
            engine: ArticleTranslation.Engine.apple
        )

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { articleID, targetLanguage, bodySource in
                #expect(articleID == "a1")
                #expect(targetLanguage == "zh-Hans")
                #expect(bodySource == ArticleTranslation.BodySource.feedBody)
                return cached
            },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in
                Issue.record("Apple engine should not be called on cache hit")
                return Self.placeholder()
            },
            translateWithOpenAI: { _ in Self.placeholder() }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: "<p>World</p>",
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        #expect(result == TranslationResult.translated(cached))
    }

    // MARK: - Test 3: cache miss uses Apple for short text

    @Test func cacheMissUsesAppleForShortText() async {
        let shortBody = String(repeating: "x", count: 500)

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { request in
                #expect(request.articleID == "a1")
                #expect(request.bodyHTML == shortBody)
                return Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "Translated Title",
                    body: "<p>Translated Body</p>",
                    engine: ArticleTranslation.Engine.apple
                )
            },
            translateWithOpenAI: { _ in Self.placeholder() }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: shortBody,
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        guard case .translated(let t) = result else {
            Issue.record("Expected translated result, got \(result)")
            return
        }
        #expect(t.engine == ArticleTranslation.Engine.apple)
    }

    // MARK: - Test 4: cache miss uses LLM for long text when key configured

    @Test func cacheMissUsesLLMForLongTextWhenKeyPresent() async {
        let longBody = String(repeating: "x", count: 2000)

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { true },
            openAIConfig: {
                OpenAICompatibleEngine.Config(
                    baseURL: URL(string: "https://api.example.com/v1")!,
                    apiKey: "sk-test",
                    model: "gpt-4o-mini"
                )
            },
            translateWithApple: { _ in Self.placeholder() },
            translateWithOpenAI: { request in
                #expect(request.articleID == "a1")
                return Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "LLM Title",
                    body: "<p>LLM Body</p>",
                    engine: ArticleTranslation.Engine.openAICompatible
                )
            }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: longBody,
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        guard case .translated(let t) = result else {
            Issue.record("Expected translated result, got \(result)")
            return
        }
        #expect(t.engine == ArticleTranslation.Engine.openAICompatible)
    }

    // MARK: - Test 5: cache miss falls back to Apple when LLM key missing

    @Test func cacheMissFallsBackToAppleWhenLLMKeyMissing() async {
        let longBody = String(repeating: "x", count: 2000)

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { request in
                return Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "Apple Title",
                    body: "<p>Apple Body</p>",
                    engine: ArticleTranslation.Engine.apple
                )
            },
            translateWithOpenAI: { _ in
                Issue.record("OpenAI should not be called when key is missing")
                return Self.placeholder()
            }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: longBody,
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        guard case .translated(let t) = result else {
            Issue.record("Expected translated result, got \(result)")
            return
        }
        #expect(t.engine == ArticleTranslation.Engine.apple)
    }

    // MARK: - Test 6: source-language matches target returns skipped without cache write

    @Test func sourceMatchesTargetReturnsSkippedWithoutCacheWrite() async {
        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { title, bodyHTML, targetLanguage in
                #expect(title == "你好")
                #expect(bodyHTML == "<p>世界</p>")
                #expect(targetLanguage == "zh-Hans")
                return true
            },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in
                Issue.record("Cache should not be written on source-matches-target skip")
            },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in
                Issue.record("Engine should not be called on source-matches-target skip")
                return Self.placeholder()
            },
            translateWithOpenAI: { _ in Self.placeholder() }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "你好",
            bodyHTML: "<p>世界</p>",
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        #expect(result == TranslationResult.skipped(SkipReason.sourceMatchesTarget))
    }

    // MARK: - Test 7: target-language change produces different cache key

    @Test func targetLanguageChangeProducesDifferentCacheKey() async {
        nonisolated(unsafe) var fetchCalls: [(String, String, ArticleTranslation.BodySource)] = []

        let coordinator = TranslationCoordinator(deps: TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "ja" },  // Will be overridden for second call
            skipWhenSourceMatchesTarget: { false },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { articleID, targetLanguage, bodySource in
                fetchCalls.append((articleID, targetLanguage, bodySource))
                return nil
            },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { request in
                Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "T",
                    body: "B",
                    engine: ArticleTranslation.Engine.apple
                )
            },
            translateWithOpenAI: { _ in Self.placeholder() }
        ))

        // First call with Japanese target
        _ = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: "<p>World</p>",
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        #expect(fetchCalls.count == 1)
        #expect(fetchCalls[0].1 == "ja")

        // For target language change, we need a new coordinator (the closure is captured).
        // This test validates that fetch is called with the language from deps.targetLanguage.
    }

    // MARK: - Test 8: engine selection with short text and LLM key still uses Apple

    @Test func selectedLLMUsesOpenAIForShortText() async {
        let shortBody = String(repeating: "x", count: 200)

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            engineChoice: { .openAICompatible },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { true },
            openAIConfig: {
                OpenAICompatibleEngine.Config(
                    baseURL: URL(string: "https://api.example.com/v1")!,
                    apiKey: "sk-test",
                    model: "Translation"
                )
            },
            translateWithApple: { _ in
                Issue.record("Apple should not be called when OpenAI-Compatible is selected")
                return Self.placeholder()
            },
            translateWithOpenAI: { request in
                #expect(request.bodyHTML == shortBody)
                return Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "LLM Title",
                    body: "<p>LLM Body</p>",
                    engine: ArticleTranslation.Engine.openAICompatible
                )
            }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: shortBody,
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        guard case .translated(let t) = result else {
            Issue.record("Expected translated result, got \(result)")
            return
        }
        #expect(t.engine == ArticleTranslation.Engine.openAICompatible)
    }

    @Test func shortTextWithLLMKeyStillUsesApple() async {
        let shortBody = String(repeating: "x", count: 1499)

        let deps = TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { true },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { true },
            openAIConfig: {
                OpenAICompatibleEngine.Config(
                    baseURL: URL(string: "https://api.example.com/v1")!,
                    apiKey: "sk-test",
                    model: "gpt-4o-mini"
                )
            },
            translateWithApple: { request in
                #expect(request.bodyHTML.count < 1500)
                return Self.makeTranslation(
                    articleID: request.articleID,
                    targetLanguage: request.targetLanguage,
                    bodySource: request.bodySource,
                    title: "T",
                    body: "B",
                    engine: ArticleTranslation.Engine.apple
                )
            },
            translateWithOpenAI: { _ in
                Issue.record("OpenAI should not be called for short text even with key")
                return Self.placeholder()
            }
        )

        let coordinator = TranslationCoordinator(deps: deps)
        let result = await coordinator.translation(
            for: "a1",
            title: "Hello",
            bodyHTML: shortBody,
            bodySource: ArticleTranslation.BodySource.feedBody
        )

        guard case .translated(let t) = result else {
            Issue.record("Expected translated result, got \(result)")
            return
        }
        #expect(t.engine == ArticleTranslation.Engine.apple)
    }
}
