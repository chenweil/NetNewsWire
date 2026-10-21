//
//  ArticleComment.swift
//  NetNewsWire
//
//  The comment model shared by every comments provider.
//

import Foundation

/// A single comment in an article's comment thread.
///
/// Comments are gathered by a `CommentsProvider` and rendered into the
/// article view, below the article body.
struct ArticleComment: Identifiable, Hashable, Sendable {

	/// Identifier that is unique within the thread. Providers are responsible
	/// for making it stable across fetches, so the same comment is not
	/// duplicated when the thread is refreshed.
	let id: String

	/// Display name of the author. Empty when the source did not provide one.
	let authorName: String

	/// Avatar image for the author, when the source provides one.
	let authorAvatarURL: URL?

	/// Profile page for the author, when the source provides one.
	let authorURL: URL?

	/// Comment body as HTML. Providers are responsible for making sure this
	/// is safe to inject into the article view.
	let bodyHTML: String

	/// When the comment was posted, when the source provides a date.
	let date: Date?

	/// Link to the comment on the original site.
	let permalink: URL?

	/// Replies to this comment.
	let replies: [ArticleComment]

	init(
		id: String,
		authorName: String = "",
		authorAvatarURL: URL? = nil,
		authorURL: URL? = nil,
		bodyHTML: String,
		date: Date? = nil,
		permalink: URL? = nil,
		replies: [ArticleComment] = []
	) {
		self.id = id
		self.authorName = authorName
		self.authorAvatarURL = authorAvatarURL
		self.authorURL = authorURL
		self.bodyHTML = bodyHTML
		self.date = date
		self.permalink = permalink
		self.replies = replies
	}

	/// Number of comments in this subtree, including this one.
	var totalCount: Int {
		1 + replies.reduce(0) { $0 + $1.totalCount }
	}

	/// This comment and all of its replies, depth first.
	var flattened: [ArticleComment] {
		[self] + replies.flatMap(\.flattened)
	}
}
