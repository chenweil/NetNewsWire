//
//  CommentsService.swift
//  NetNewsWire
//
//  Picks the comments provider for an article and fetches the thread.
//

import Foundation

/// Resolves an article URL to a comments provider and fetches the thread.
///
/// The service is deliberately conservative: it asks each provider whether it
/// can serve a URL *before* any network request is made, so opening an
/// article never triggers a download of the original page unless a provider
/// has explicitly claimed that URL.
struct CommentsService: Sendable {

	/// The providers, in priority order. The first one that can serve a URL
	/// wins.
	let providers: [any CommentsProvider]

	/// Threads already fetched in this session, so re-opening an article does
	/// not hit the network again.
	let cache: CommentsCache

	init(providers: [any CommentsProvider], cache: CommentsCache = CommentsCache()) {
		self.providers = providers
		self.cache = cache
	}

	/// The service used by the app.
	static let shared = CommentsService(providers: [V2EXCommentsProvider()])

	/// The provider that can serve comments for the given article URL.
	func provider(for articleURL: URL) -> (any CommentsProvider)? {
		providers.first { $0.canProvideComments(for: articleURL) }
	}

	/// The comment thread for the article, oldest first. Empty when no
	/// provider serves the URL or when the fetch fails.
	func comments(for articleURL: URL) async -> [ArticleComment] {
		if let cached = await cache.thread(for: articleURL) {
			return cached
		}
		guard let provider = provider(for: articleURL) else { return [] }
		let comments = (try? await provider.fetchComments(for: articleURL)) ?? []
		// Only successful, non-empty threads are cached: a failed fetch
		// should be retried the next time the article is opened.
		if !comments.isEmpty {
			await cache.store(comments, for: articleURL)
		}
		return comments
	}
}

/// Caches comment threads for the current session.
actor CommentsCache {

	private var threads: [URL: [ArticleComment]] = [:]

	/// The cached thread for the URL, if there is one.
	func thread(for articleURL: URL) -> [ArticleComment]? {
		threads[articleURL]
	}

	/// Caches the thread for the URL.
	func store(_ comments: [ArticleComment], for articleURL: URL) {
		threads[articleURL] = comments
	}
}
