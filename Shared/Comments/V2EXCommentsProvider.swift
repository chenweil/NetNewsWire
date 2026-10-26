//
//  V2EXCommentsProvider.swift
//  NetNewsWire
//
//  Comments for V2EX topics.
//
//  V2EX publishes a feed per node, and each feed item contains only the first
//  post of a topic. The replies — the part readers actually care about — live
//  on the topic page and are exposed by a public JSON endpoint. This provider
//  fetches them and falls back to parsing the topic page when the JSON
//  endpoint is unavailable.
//

import Foundation
import RSWeb

/// Provides the replies of a V2EX topic.
struct V2EXCommentsProvider: CommentsProvider {

	let identifier = "v2ex"
	let displayName = "V2EX"

	/// Session used for network requests. Injectable so tests can stub it.
	let session: URLSession

	init(session: URLSession = .makeWebserviceSession()) {
		self.session = session
	}

	// MARK: - CommentsProvider

	func canProvideComments(for articleURL: URL) -> Bool {
		topicID(for: articleURL) != nil
	}

	func fetchComments(for articleURL: URL) async throws -> [ArticleComment] {
		guard let topicID = topicID(for: articleURL) else { return [] }

		let replies = await fetchRepliesFromAPI(topicID: topicID)
		if !replies.isEmpty {
			return replies
		}

		return await fetchRepliesFromTopicPage(topicID: topicID)
	}

	// MARK: - Topic

	/// The topic ID in a V2EX topic URL, e.g. `1249625` for
	/// `https://www.v2ex.com/t/1249625#reply5`.
	func topicID(for articleURL: URL) -> Int? {
		guard let host = articleURL.host?.lowercased(), host == "v2ex.com" || host == "www.v2ex.com" else {
			return nil
		}
		let components = articleURL.pathComponents
		guard let index = components.firstIndex(of: "t"), index + 1 < components.count else {
			return nil
		}
		return Int(components[index + 1])
	}

	/// The page that shows a topic and its replies.
	static func topicPageURL(topicID: Int) -> URL? {
		URL(string: "https://www.v2ex.com/t/\(topicID)")
	}

	/// The public endpoint that returns the replies of a topic.
	static func repliesEndpoint(topicID: Int) -> URL? {
		var components = URLComponents(string: "https://www.v2ex.com/api/replies/show.json")
		components?.queryItems = [
			URLQueryItem(name: "topic_id", value: String(topicID)),
			URLQueryItem(name: "page", value: "1"),
		]
		return components?.url
	}

	// MARK: - JSON API

	private struct Reply: Decodable {
		struct Member: Decodable {
			let username: String
			let avatar_normal: String?
			let url: String?
		}

		let id: Int
		let created: TimeInterval
		let content: String?
		let content_rendered: String?
		let member: Member?
	}

	private func fetchRepliesFromAPI(topicID: Int) async -> [ArticleComment] {
		guard let endpoint = Self.repliesEndpoint(topicID: topicID) else { return [] }

		guard
			let (data, response) = try? await session.data(from: endpoint),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let replies = try? JSONDecoder().decode([Reply].self, from: data)
		else {
			return []
		}

		return replies.compactMap { comment(for: $0, topicID: topicID) }
	}

	private func comment(for reply: Reply, topicID: Int) -> ArticleComment? {
		let body = reply.content_rendered ?? reply.content ?? ""
		guard !body.isEmpty else { return nil }

		let authorName = reply.member?.username ?? ""
		let permalink = URL(string: "https://www.v2ex.com/t/\(topicID)#reply\(reply.id)")

		return ArticleComment(
			id: "v2ex-\(reply.id)",
			authorName: authorName,
			authorAvatarURL: reply.member?.avatar_normal.flatMap(Self.imageURL(from:)),
			authorURL: reply.member?.url.flatMap(Self.imageURL(from:)),
			bodyHTML: CommentHTMLSanitizer.sanitized(body),
			date: Date(timeIntervalSince1970: reply.created),
			permalink: permalink
		)
	}

	// MARK: - Topic page fallback

	private func fetchRepliesFromTopicPage(topicID: Int) async -> [ArticleComment] {
		guard
			let url = Self.topicPageURL(topicID: topicID),
			let (data, response) = try? await session.data(from: url),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let html = String(data: data, encoding: .utf8)
		else {
			return []
		}

		return commentsFromTopicPageHTML(html, topicID: topicID)
	}

	/// Extracts the replies from a V2EX topic page.
	func commentsFromTopicPageHTML(_ html: String, topicID: Int) -> [ArticleComment] {
		let elements = HTMLElementParser.allElements(in: html)

		var comments: [ArticleComment] = []
		for cell in elements where cell.hasClass("cell") {
			guard
				let bodyElement = cell.descendants(where: { $0.hasClass("reply_content") }).first
			else {
				continue
			}

			let body = bodyElement.innerHTML.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !body.isEmpty else { continue }

			let replyID = cell.attribute("id")?.replacingOccurrences(of: "r_", with: "") ?? ""
			let authorElement = cell.descendants(where: { $0.name == "a" && ($0.attribute("href")?.hasPrefix("/member/") ?? false) }).first
			let authorName = authorElement?.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			let avatarURL = cell.descendants(where: { $0.hasClass("avatar") }).first?.attribute("src").flatMap(Self.imageURL(from:))
			let date = cell.descendants(where: { $0.hasClass("ago") }).first?.attribute("title").flatMap(Self.v2exDate(from:))

			let permalink = replyID.isEmpty
				? URL(string: "https://www.v2ex.com/t/\(topicID)")
				: URL(string: "https://www.v2ex.com/t/\(topicID)#reply\(replyID)")

			comments.append(ArticleComment(
				id: "v2ex-\(replyID)",
				authorName: authorName,
				authorAvatarURL: avatarURL,
				authorURL: authorElement.flatMap { $0.attribute("href") }.flatMap { URL(string: "https://www.v2ex.com\($0)") },
				bodyHTML: CommentHTMLSanitizer.sanitized(body),
				date: date,
				permalink: permalink
			))
		}

		return comments
	}

	// MARK: - Helpers

	/// Returns a URL for an image or link found in the API payload, but only
	/// for `http`/`https` URLs.
	static func imageURL(from string: String) -> URL? {
		guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			return nil
		}
		return url
	}

	/// Parses a V2EX date such as `2026-10-17 18:37:32 +08:00`.
	static func v2exDate(from string: String) -> Date? {
		// V2EX writes the offset with a colon; ISO 8601 basic format does not.
		for format in ["yyyy-MM-dd HH:mm:ss xxx", "yyyy-MM-dd HH:mm:ss Z"] {
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.dateFormat = format
			if let date = formatter.date(from: string) {
				return date
			}
		}
		return nil
	}
}
