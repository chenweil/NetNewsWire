//
//  OpenAICompatibleEngine.swift
//  NetNewsWire
//
//  Translation engine backed by any OpenAI-Chat-Completions-compatible
//  HTTP API (OpenAI, DeepSeek, OpenRouter, custom gateways, local Ollama
//  via relay). The body is sent as opaque plain text per the issue spec
//  — HTML tags survive the round-trip as literal characters that the
//  model sees and the caller renders as-is.
//
//  The HTTP layer is wrapped behind `sendChat` so unit tests run without
//  the network. Production code uses `OpenAICompatibleEngine.live(config:)`
//  which builds a real `URLSession` request.
//

import Foundation
import ArticlesDatabase

public final class OpenAICompatibleEngine: TranslationEngine, Sendable {

	// MARK: - Public types

	/// Settings the engine needs at translation time. Read fresh on every
	/// `translate` call so preference edits take effect immediately.
	public struct Config: Sendable {
		public let baseURL: URL
		public let apiKey: String
		public let model: String
		public init(baseURL: URL, apiKey: String, model: String) {
			self.baseURL = baseURL
			self.apiKey = apiKey
			self.model = model
		}
	}

	/// One Chat-Completions message. `role` is `.system` / `.user` / `.assistant`.
	public struct Message: Sendable {
		public enum Role: String, Sendable {
			case system
			case user
			case assistant
		}
		public let role: Role
		public let content: String
		public init(role: Role, content: String) {
			self.role = role
			self.content = content
		}
	}

	/// Low-level transport error. Mapped to `TranslationError` at the engine
	/// boundary so callers see only the engine's own error vocabulary.
	public enum HTTPError: Error, Equatable, Sendable {
		case statusCode(Int)
		case network(URLError.Code)
		case malformedResponse
	}

	// MARK: - Init

	/// `(config, messages) -> assistant text`. Throws `HTTPError`; the
	/// engine translates that into `TranslationError` for callers.
	private let sendChat: @Sendable (Config, [Message]) async throws -> String
	/// `(config, messages) -> assistant text stream`. The stream yields only
	/// assistant content deltas; transport and SSE parsing stay inside the
	/// engine.
	private let streamChat: @Sendable (Config, [Message]) -> AsyncThrowingStream<String, Error>

	public init(
		config: Config,
		sendChat: @escaping @Sendable (Config, [Message]) async throws -> String,
		streamChat: @escaping @Sendable (Config, [Message]) -> AsyncThrowingStream<String, Error> = { _, _ in
			AsyncThrowingStream { continuation in
				continuation.finish(throwing: HTTPError.malformedResponse)
			}
		}
	) {
		self.config = config
		self.sendChat = sendChat
		self.streamChat = streamChat
	}

	public let config: Config

	// MARK: - TranslationEngine

	public func translate(_ request: TranslationRequest) async throws -> ArticleTranslation {
		guard !config.apiKey.isEmpty else {
			throw TranslationError.credentialsMissing
		}

		let systemPrompt = Self.systemPrompt(targetLanguage: request.targetLanguage)

		// Title and body are sent as two separate requests per the issue spec.
		// The OpenAI Chat Completions API treats each call as stateless, so
		// splitting doesn't lose context but keeps prompt-token usage low on
		// short titles.
		let translatedTitle = try await translateText(
			systemPrompt: systemPrompt,
			userText: request.title,
			config: config,
			messages: [
				Message(role: .system, content: systemPrompt),
				Message(role: .user, content: request.title),
			]
		)
		let translatedBody = try await translateText(
			systemPrompt: systemPrompt,
			userText: request.bodyHTML,
			config: config,
			messages: [
				Message(role: .system, content: systemPrompt),
				Message(role: .user, content: request.bodyHTML),
			]
		)
		return ArticleTranslation(
			articleID: request.articleID,
			targetLanguage: request.targetLanguage,
			bodySource: request.bodySource,
			title: translatedTitle,
			body: translatedBody,
			engine: .openAICompatible,
			translatedAt: Date()
		)
	}

	/// Translates the title normally and streams the body as assistant content
	/// deltas. The returned translation is complete and suitable for caching;
	/// callers should use `onBodyDelta` only for temporary display.
	public func translateStreaming(
		_ request: TranslationRequest,
		onBodyDelta: @escaping @Sendable (String) async -> Void
	) async throws -> ArticleTranslation {
		guard !config.apiKey.isEmpty else {
			throw TranslationError.credentialsMissing
		}

		let systemPrompt = Self.systemPrompt(targetLanguage: request.targetLanguage)
		let translatedTitle = try await translateText(
			systemPrompt: systemPrompt,
			userText: request.title,
			config: config,
			messages: [
				Message(role: .system, content: systemPrompt),
				Message(role: .user, content: request.title),
			]
		)
		let translatedBody = try await translateTextStreaming(
			userText: request.bodyHTML,
			config: config,
			messages: [
				Message(role: .system, content: systemPrompt),
				Message(role: .user, content: request.bodyHTML),
			],
			onDelta: onBodyDelta
		)

		return ArticleTranslation(
			articleID: request.articleID,
			targetLanguage: request.targetLanguage,
			bodySource: request.bodySource,
			title: translatedTitle,
			body: translatedBody,
			engine: .openAICompatible,
			translatedAt: Date()
		)
	}

	private func translateText(
		systemPrompt: String,
		userText: String,
		config: Config,
		messages: [Message]
	) async throws -> String {
		// Empty input short-circuits — many APIs refuse empty `messages`.
		guard !userText.isEmpty else { return "" }
		do {
			return try await sendChat(config, messages)
		} catch let error as HTTPError {
			throw Self.translateHTTPError(error)
		}
	}

	private func translateTextStreaming(
		userText: String,
		config: Config,
		messages: [Message],
		onDelta: @escaping @Sendable (String) async -> Void
	) async throws -> String {
		guard !userText.isEmpty else { return "" }

		var translatedText = ""
		do {
			for try await delta in streamChat(config, messages) {
				translatedText.append(delta)
				await onDelta(delta)
			}
		} catch let error as HTTPError {
			throw Self.translateHTTPError(error)
		}
		return translatedText
	}

	static func translateHTTPError(_ error: HTTPError) -> TranslationError {
		switch error {
		case .statusCode(429):
			return .rateLimited
		case .statusCode(401), .statusCode(403):
			return .credentialsMissing
		case .statusCode:
			return .invalidResponse
		case .network(.timedOut):
			return .requestTimedOut
		case .network:
			return .networkUnavailable
		case .malformedResponse:
			return .invalidResponse
		}
	}

	// MARK: - Prompt

	/// Per the issue spec: "Translate from English to {target}. Preserve
	/// formatting. Output only the translation."
	static func systemPrompt(targetLanguage: String) -> String {
		"Translate from English to \(targetLanguage). Preserve formatting. Output only the translation."
	}
}

// MARK: - Production factory

extension OpenAICompatibleEngine {

	/// Real engine backed by `URLSession`.
	///
	/// Hardcoded: `temperature = 0.2`, `timeout = 120s`. These were decided
	/// during grilling and aren't exposed in preferences — changing them
	/// requires editing this file.
	public static func live(config: Config) -> OpenAICompatibleEngine {
		let timeout: TimeInterval = 120
		let temperature: Double = 0.2

		return OpenAICompatibleEngine(
			config: config,
			sendChat: { config, messages in
				let url = config.baseURL.appendingPathComponent("chat/completions")
				var request = URLRequest(url: url, timeoutInterval: timeout)
				request.httpMethod = "POST"
				request.setValue("application/json", forHTTPHeaderField: "Content-Type")
				request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

				let body: [String: Any] = [
					"model": config.model,
					"messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
					"temperature": temperature,
				]
				request.httpBody = try JSONSerialization.data(withJSONObject: body)

				let (data, response): (Data, URLResponse)
				do {
					(data, response) = try await URLSession.shared.data(for: request)
				} catch let urlError as URLError {
					throw HTTPError.network(urlError.code)
				}

				guard let http = response as? HTTPURLResponse else {
					throw HTTPError.malformedResponse
				}
				guard (200..<300).contains(http.statusCode) else {
					throw HTTPError.statusCode(http.statusCode)
				}

				return try Self.extractAssistantText(from: data)
			},
			streamChat: { config, messages in
				Self.makeStreamingResponse(
					config: config,
					messages: messages,
					timeout: timeout,
					temperature: temperature
				)
			}
		)
	}

	private static func makeStreamingResponse(
		config: Config,
		messages: [Message],
		timeout: TimeInterval,
		temperature: Double
	) -> AsyncThrowingStream<String, Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					let url = config.baseURL.appendingPathComponent("chat/completions")
					var request = URLRequest(url: url, timeoutInterval: timeout)
					request.httpMethod = "POST"
					request.setValue("application/json", forHTTPHeaderField: "Content-Type")
					request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

					let body: [String: Any] = [
						"model": config.model,
						"messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
						"temperature": temperature,
						"stream": true,
					]
					request.httpBody = try JSONSerialization.data(withJSONObject: body)

					let (bytes, response) = try await URLSession.shared.bytes(for: request)
					guard let http = response as? HTTPURLResponse else {
						throw HTTPError.malformedResponse
					}
					guard (200..<300).contains(http.statusCode) else {
						throw HTTPError.statusCode(http.statusCode)
					}

					for try await line in bytes.lines {
						if Self.isStreamingDoneLine(line) {
							break
						}
						if let delta = Self.extractStreamingDelta(from: line) {
							continuation.yield(delta)
						}
					}
					continuation.finish()
				} catch is CancellationError {
					continuation.finish()
				} catch let error as HTTPError {
					continuation.finish(throwing: error)
				} catch let error as URLError {
					continuation.finish(throwing: HTTPError.network(error.code))
				} catch {
					continuation.finish(throwing: HTTPError.malformedResponse)
				}
			}
			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	/// Parses the OpenAI Chat-Completions response and returns the
	/// assistant's `content` string. Throws `.malformedResponse` if the
	/// shape doesn't match what we asked for.
	static func extractAssistantText(from data: Data) throws -> String {
		guard
			let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			let choices = json["choices"] as? [[String: Any]],
			let first = choices.first,
			let message = first["message"] as? [String: Any],
			let content = message["content"] as? String
		else {
			throw HTTPError.malformedResponse
		}
		return content
	}

	/// Extracts assistant content from one OpenAI-compatible SSE `data:` line.
	/// Role-only deltas and `[DONE]` produce no content and are ignored.
	static func extractStreamingDelta(from line: String) -> String? {
		let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmedLine.hasPrefix("data:") else { return nil }

		let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
		guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
			return nil
		}
		guard
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let choices = json["choices"] as? [[String: Any]],
			let first = choices.first,
			let delta = first["delta"] as? [String: Any],
			let content = delta["content"] as? String
		else {
			return nil
		}
		return content
	}

	private static func isStreamingDoneLine(_ line: String) -> Bool {
		let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmedLine.hasPrefix("data:") else { return false }
		let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
		return payload == "[DONE]"
	}
}
