//
//  OpenAICompatibleEngineTests.swift
//  NetNewsWireTests
//
//  Tests for the OpenAI-compatible translation engine. The HTTP layer is
//  injected so tests run without hitting the network — production code uses
//  `OpenAICompatibleEngine.live(config:)` which makes a real POST.
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite struct OpenAICompatibleEngineTests {

	// MARK: - Helpers

	private static let testConfig = OpenAICompatibleEngine.Config(
		baseURL: URL(string: "https://api.example.com/v1")!,
		apiKey: "sk-test",
		model: "gpt-4o-mini"
	)

	/// Mock `sendChat` closure that captures every (config, messages) call
	/// and returns a canned response. The canned response is the user
	/// message with a tag appended — this lets each test assert what was
	/// sent and that the result was assembled correctly.
	private final class ChatRecorder: @unchecked Sendable {
		var calls: [(config: OpenAICompatibleEngine.Config, messages: [OpenAICompatibleEngine.Message])] = []
		var nextResponse: String = ""

		func send(
			config: OpenAICompatibleEngine.Config,
			messages: [OpenAICompatibleEngine.Message]
		) async throws -> String {
			calls.append((config, messages))
			return nextResponse
		}
	}

	// MARK: - Basic translation

	@Test func translatesTitleAndBodyAsSeparateRequests() async throws {
		let recorder = ChatRecorder()
		recorder.nextResponse = "TRANSLATED"
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: recorder.send(config:messages:))

		let result = try await engine.translate(TranslationRequest(
			articleID: "a1",
			title: "Hello world",
			bodyHTML: "<p>Body text.</p>",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))

		#expect(recorder.calls.count == 2)
		#expect(result.title == "TRANSLATED")
		#expect(result.body == "TRANSLATED")
		#expect(result.engine == .openAICompatible)
		#expect(result.articleID == "a1")
		#expect(result.targetLanguage == "zh-Hans")
		#expect(result.bodySource == .feedBody)
	}

	@Test func titleRequestSendsTitleOnly() async throws {
		let recorder = ChatRecorder()
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: recorder.send(config:messages:))

		_ = try await engine.translate(TranslationRequest(
			articleID: "a",
			title: "Original Title",
			bodyHTML: "<p>Body.</p>",
			targetLanguage: "ja",
			bodySource: .feedBody
		))

		// First call is the title request.
		let titleCall = recorder.calls[0]
		#expect(titleCall.messages.count == 2)
		#expect(titleCall.messages[0].role == .system)
		#expect(titleCall.messages[1].role == .user)
		#expect(titleCall.messages[1].content == "Original Title")
	}

	@Test func bodyRequestSendsRawBodyAsOpaqueText() async throws {
		let recorder = ChatRecorder()
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: recorder.send(config:messages:))

		_ = try await engine.translate(TranslationRequest(
			articleID: "a",
			title: "T",
			bodyHTML: "<p>HTML body with <strong>tags</strong>.</p>",
			targetLanguage: "zh-Hans",
			bodySource: .feedBody
		))

		// Second call is the body request — body sent as opaque plain text,
		// HTML tags included (issue spec: "treats body as opaque plain text").
		let bodyCall = recorder.calls[1]
		#expect(bodyCall.messages[1].content == "<p>HTML body with <strong>tags</strong>.</p>")
	}

	@Test func systemPromptContainsTargetLanguage() async throws {
		let recorder = ChatRecorder()
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: recorder.send(config:messages:))

		_ = try await engine.translate(TranslationRequest(
			articleID: "a",
			title: "T",
			bodyHTML: "B",
			targetLanguage: "fr",
			bodySource: .feedBody
		))

		let systemPrompt = recorder.calls[0].messages[0].content
		#expect(systemPrompt.contains("fr"))
	}

	// MARK: - Error mapping

	@Test func missingAPIKeyThrowsCredentialsMissing() async throws {
		let config = OpenAICompatibleEngine.Config(
			baseURL: URL(string: "https://api.example.com/v1")!,
			apiKey: "",
			model: "gpt-4o-mini"
		)
		let engine = OpenAICompatibleEngine(config: config, sendChat: { _, _ in "x" })

		await #expect(throws: TranslationError.credentialsMissing) {
			try await engine.translate(TranslationRequest(
				articleID: "a",
				title: "T",
				bodyHTML: "B",
				targetLanguage: "zh-Hans",
				bodySource: .feedBody
			))
		}
	}

	@Test func http429MapsToRateLimited() async throws {
		let send: @Sendable (OpenAICompatibleEngine.Config, [OpenAICompatibleEngine.Message]) async throws -> String = { _, _ in
			throw OpenAICompatibleEngine.HTTPError.statusCode(429)
		}
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: send)

		await #expect(throws: TranslationError.rateLimited) {
			try await engine.translate(TranslationRequest(
				articleID: "a",
				title: "T",
				bodyHTML: "B",
				targetLanguage: "zh-Hans",
				bodySource: .feedBody
			))
		}
	}

	@Test func http500MapsToInvalidResponse() async throws {
		let send: @Sendable (OpenAICompatibleEngine.Config, [OpenAICompatibleEngine.Message]) async throws -> String = { _, _ in
			throw OpenAICompatibleEngine.HTTPError.statusCode(500)
		}
		let engine = OpenAICompatibleEngine(config: Self.testConfig, sendChat: send)

		await #expect(throws: TranslationError.invalidResponse) {
			try await engine.translate(TranslationRequest(
				articleID: "a",
				title: "T",
				bodyHTML: "B",
				targetLanguage: "zh-Hans",
				bodySource: .feedBody
			))
		}
	}
}