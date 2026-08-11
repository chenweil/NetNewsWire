//
//  DetailWebViewControllerTranslationTests.swift
//  NetNewsWireTests
//
//  Tests for translation integration in the article detail view.
//  Uses a mock TranslationCoordinator to verify status transitions,
//  JS bridge calls, and retry behavior without hitting real APIs.
//

import Foundation
import Testing
@testable import NetNewsWire
import ArticlesDatabase
import Articles

@Suite("DetailWebViewController translation integration")
@MainActor
struct DetailWebViewControllerTranslationTests {

    // MARK: - Test Helpers

    /// Creates a mock TranslationCoordinator that returns a predictable translation.
    private func makeMockCoordinator(
        result: TranslationResult,
        shouldCache: Bool = false
    ) -> TranslationCoordinator {
        let translation = ArticleTranslation(
            articleID: "test-article-id",
            targetLanguage: "zh-Hans",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "测试标题",
            body: "<p>测试内容</p>",
            engine: ArticleTranslation.Engine.apple,
            translatedAt: Date()
        )

        return TranslationCoordinator(deps: TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { false },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in
                guard shouldCache else { return nil }
                if case .translated(let cachedTranslation) = result {
                    return cachedTranslation
                }
                return translation
            },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in
                switch result {
                case .translated(let t):
                    return t
                case .failed(let error):
                    throw error
                default:
                    return translation
                }
            },
            translateWithOpenAI: { _ in translation }
        ))
    }

    /// Creates a test article for use in tests.
    private func makeTestArticle() -> Article {
        let status = ArticleStatus(articleID: "test-article-id", read: false, starred: false, dateArrived: Date())
        return Article(
            accountID: "test-account-id",
            articleID: "test-article-id",
            feedID: "test-feed-id",
            uniqueID: "test-unique-id",
            title: "Test Article Title",
            contentHTML: "<p>This is test content in English.</p>",
            contentText: nil,
            markdown: nil,
            url: nil,
            externalURL: nil,
            summary: nil,
            imageURL: nil,
            datePublished: Date(),
            dateModified: nil,
            authors: nil,
            status: status
        )
    }

    // MARK: - Test 1: Status updates when article changes

    @Test("Translation status updates when article loads")
    func translationStatusUpdatesWhenArticleLoads() async throws {
        // Given: A mock coordinator that will return a translation
        let expectedTranslation = ArticleTranslation(
            articleID: "test-article-id",
            targetLanguage: "zh-Hans",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "测试标题",
            body: "<p>测试内容</p>",
            engine: ArticleTranslation.Engine.apple,
            translatedAt: Date()
        )

        let mockCoordinator = makeMockCoordinator(result: .translated(expectedTranslation))
        let controller = DetailWebViewController(translationCoordinator: mockCoordinator)

        // When: Article state is set
        controller.state = .article(makeTestArticle(), nil)

        let status = try await waitForCompletedTranslationStatus(in: controller)

        switch status {
        case .translated(let translation):
            #expect(translation.articleID == expectedTranslation.articleID)
            #expect(translation.title == expectedTranslation.title)
            #expect(translation.body == expectedTranslation.body)
            #expect(translation.engine == expectedTranslation.engine)
        case .failed(let error):
            Issue.record("Translation should succeed, but got error: \(error)")
        case .streamingFailed(let error, _):
            Issue.record("Translation should succeed, but got streaming error: \(error)")
        case .idle, .translating:
            Issue.record("Translation should complete, but status is: \(status)")
        }
    }

    // MARK: - Test 2: Cache hit displays immediately

    @Test("Cached translation displays immediately without translating state")
    func cachedTranslationDisplaysImmediately() async throws {
        // Given: A coordinator that will return a cached translation
        let cachedTranslation = ArticleTranslation(
            articleID: "test-article-id",
            targetLanguage: "zh-Hans",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "缓存的标题",
            body: "<p>缓存的内容</p>",
            engine: ArticleTranslation.Engine.apple,
            translatedAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )

        let mockCoordinator = makeMockCoordinator(
            result: .translated(cachedTranslation),
            shouldCache: true
        )

        let controller = DetailWebViewController(translationCoordinator: mockCoordinator)

        // When: Article state is set
        controller.state = .article(makeTestArticle(), nil)

        let status = try await waitForCompletedTranslationStatus(in: controller)

        switch status {
        case .translated(let translation):
            #expect(translation.articleID == cachedTranslation.articleID)
            #expect(translation.title == cachedTranslation.title)
            // The cached translation should be used
            #expect(translation.translatedAt == cachedTranslation.translatedAt)
        case .translating:
            Issue.record("Cache hit should not go through .translating state")
        case .idle, .failed, .streamingFailed:
            Issue.record("Cache hit should result in .translated state, got: \(status)")
        }
    }

    // MARK: - Test 3: Disabled translation remains idle

    @Test("Translation remains idle when disabled")
    func translationRemainsIdleWhenDisabled() async throws {
        // Given: A coordinator where translation is disabled
        let disabledDeps = TranslationCoordinator.Dependencies(
            isEnabled: { false },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { false },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in
                Issue.record("Should not call translation engine when disabled")
                return ArticleTranslation(
                    articleID: "", targetLanguage: "", bodySource: .feedBody,
                    title: "", body: "", engine: .apple, translatedAt: Date()
                )
            },
            translateWithOpenAI: { _ in
                Issue.record("Should not call translation engine when disabled")
                return ArticleTranslation(
                    articleID: "", targetLanguage: "", bodySource: .feedBody,
                    title: "", body: "", engine: .apple, translatedAt: Date()
                )
            }
        )

        let mockCoordinator = TranslationCoordinator(deps: disabledDeps)
        let controller = DetailWebViewController(translationCoordinator: mockCoordinator)

        // When: Article state is set
        controller.state = .article(makeTestArticle(), nil)

        try await Task.sleep(for: .milliseconds(20))
        let didReturnToIdle = try await waitForTranslationStatus(in: controller) { status in
            status == .idle
        }

        // Then: Status should remain idle
        #expect(didReturnToIdle)
    }

    // MARK: - Test 4: Failed translation shows error

    @Test("Failed translation shows error status")
    func failedTranslationShowsErrorStatus() async throws {
        // Given: A coordinator that will fail
        let mockCoordinator = TranslationCoordinator(deps: TranslationCoordinator.Dependencies(
            isEnabled: { true },
            targetLanguage: { "zh-Hans" },
            skipWhenSourceMatchesTarget: { false },
            checkSourceMatchesTarget: { _, _, _ in false },
            fetchCache: { _, _, _ in nil },
            upsertCache: { _ in },
            deleteCache: { _, _, _ in },
            hasOpenAIKey: { false },
            openAIConfig: { nil },
            translateWithApple: { _ in
                throw TranslationError.networkUnavailable
            },
            translateWithOpenAI: { _ in
                throw TranslationError.networkUnavailable
            }
        ))

        let controller = DetailWebViewController(translationCoordinator: mockCoordinator)

        // When: Article state is set
        controller.state = .article(makeTestArticle(), nil)

        let status = try await waitForCompletedTranslationStatus(in: controller)

        switch status {
        case .failed(let errorMessage):
            #expect(errorMessage.contains("network") || errorMessage.contains("unavailable"))
        case .idle, .translating, .translated, .streamingFailed:
            Issue.record("Expected .failed status, got: \(status)")
        }
    }

    @Test("Translated article body uses typewriter reveal")
    func translatedArticleBodyUsesTypewriterReveal() async throws {
        let translation = ArticleTranslation(
            articleID: "test-article-id",
            targetLanguage: "zh-Hans",
            bodySource: ArticleTranslation.BodySource.feedBody,
            title: "测试 <标题>",
            body: "<p>第一段内容</p><p><strong>第二段内容</strong></p>",
            engine: ArticleTranslation.Engine.openAICompatible,
            translatedAt: Date()
        )

        let controller = DetailWebViewController()
        controller.loadViewIfNeeded()
        controller.state = .article(makeTestArticle(), nil)
        controller.translationStatus = .translated(translation)

        let didComplete = try await waitForJavaScriptBool(
            """
            (() => {
                const element = document.querySelector("[data-translation-typewriter]");
                return element?.dataset.translationTypewriterComplete === "true";
            })()
            """,
            in: controller
        )
        #expect(didComplete)

        let didKeepContentAndStructure = try await evaluateJavaScriptBool(
            """
            (() => {
                const title = document.querySelector(".articleTitle h1");
                const element = document.querySelector("[data-translation-typewriter]");
                return title?.textContent === "测试 <标题>"
                    && title?.querySelector("*") === null
                    && document.querySelector(".translationTypewriterCursor") === null
                    && element?.textContent.includes("第一段内容")
                    && element?.textContent.includes("第二段内容")
                    && element?.querySelector("strong") !== null;
            })()
            """,
            in: controller
        )
        #expect(didKeepContentAndStructure)
    }

    @Test("Translating status animates dots")
    func translatingStatusAnimatesDots() async throws {
        let controller = DetailWebViewController()
        controller.loadViewIfNeeded()
        controller.state = .article(makeTestArticle(), nil)
        controller.translationStatus = .translating

        let didAnimate = try await waitForJavaScriptBool(
            """
            (() => {
                const dots = document.querySelector("[data-translation-loading-dots]");
                return dots !== null && dots.textContent !== "...";
            })()
            """,
            in: controller,
            timeout: .seconds(2)
        )
        #expect(didAnimate)
    }

    @Test("Translating status renders streamed text safely")
    func translatingStatusRendersStreamedTextSafely() async throws {
        let controller = DetailWebViewController()
        controller.loadViewIfNeeded()
        controller.state = .article(makeTestArticle(), nil)
        controller.translationStatus = .translating

        let didRenderSafely = try await waitForJavaScriptBool(
            """
            (() => {
                const didAppend = window.appendTranslationStreamDelta("<b>partial</b>");
                const element = document.querySelector("[data-translation-stream]");
                return didAppend
                    && element?.textContent === "<b>partial</b>"
                    && element?.querySelector("b") === null;
            })()
            """,
            in: controller
        )
        #expect(didRenderSafely)
    }

    private func waitForJavaScriptBool(
        _ javascript: String,
        in controller: DetailWebViewController,
        timeout: Duration = .seconds(30)
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let result = try? await evaluateJavaScriptBool(javascript, in: controller), result {
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func waitForCompletedTranslationStatus(
        in controller: DetailWebViewController,
        timeout: Duration = .seconds(10)
    ) async throws -> TranslationStatus {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            switch controller.translationStatus {
            case .idle, .translating:
                try await Task.sleep(for: .milliseconds(20))
            case .translated, .failed, .streamingFailed:
                return controller.translationStatus
            }
        }
        return controller.translationStatus
    }

    private func waitForTranslationStatus(
        in controller: DetailWebViewController,
        timeout: Duration = .seconds(10),
        matches: (TranslationStatus) -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if matches(controller.translationStatus) {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return matches(controller.translationStatus)
    }

    private func evaluateJavaScriptBool(_ javascript: String, in controller: DetailWebViewController) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            controller.webView.evaluateJavaScript(javascript) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (result as? Bool) == true)
                }
            }
        }
    }
}
