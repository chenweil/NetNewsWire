//
//  CommentsProvider.swift
//  NetNewsWire
//
//  The extension point for comment sources.
//

import Foundation

/// A source of article comments.
///
/// A provider decides whether it can serve comments for a given article URL
/// (`canProvideComments`) and, if so, fetches the thread
/// (`fetchComments`). `CommentsService` picks the first provider that can
/// serve a URL, so adding support for a new site means adding one file and
/// registering the provider — no changes to the article view.
protocol CommentsProvider: Sendable {

	/// Stable identifier, used in logs and in the `data-comments-source`
	/// attribute of the rendered comments.
	var identifier: String { get }

	/// Human-readable name of the comment source, shown above the thread.
	var displayName: String { get }

	/// Whether this provider can supply comments for the given article URL.
	///
	/// Implementations should be cheap: they are called for every article the
	/// reader opens, before any network request is made.
	func canProvideComments(for articleURL: URL) -> Bool

	/// Fetches the comment thread for the article, oldest first.
	///
	/// Returning an empty array means "this article has no comments" — it is
	/// not an error. Throwing means the fetch failed; the reader sees no
	/// comments rather than an error.
	func fetchComments(for articleURL: URL) async throws -> [ArticleComment]
}
