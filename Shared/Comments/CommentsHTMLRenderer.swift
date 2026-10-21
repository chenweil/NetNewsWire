//
//  CommentsHTMLRenderer.swift
//  NetNewsWire
//
//  Renders a comment thread as HTML for the article view.
//

import Foundation
import RSWeb

/// Renders comment threads into the HTML shown below an article.
enum CommentsHTMLRenderer {

	/// Renders the thread, or an empty string when there is nothing to show.
	static func html(for comments: [ArticleComment], sourceName: String) -> String {
		guard !comments.isEmpty else { return "" }

		let count = comments.reduce(0) { $0 + $1.totalCount }
		let heading = NSLocalizedString("Comments", comment: "Comment thread heading")
		let countText = "\(count)"

		return """
		<section class="articleComments" data-comments-source="\(sourceName.escapedHTML)">
		<h2 class="articleCommentsHeading">\(heading.escapedHTML) <span class="articleCommentsCount">\(countText)</span></h2>
		\(listHTML(for: comments, className: "articleCommentList"))
		</section>
		"""
	}

	// MARK: - Private

	private static func listHTML(for comments: [ArticleComment], className: String) -> String {
		let items = comments.map { itemHTML(for: $0) }.joined()
		return "<ol class=\"\(className)\">\(items)</ol>"
	}

	private static func itemHTML(for comment: ArticleComment) -> String {
		let authorHTML = authorHTML(for: comment)
		let dateHTML = dateHTML(for: comment)
		let headerParts = [authorHTML, dateHTML].filter { !$0.isEmpty }
		let headerHTML = headerParts.isEmpty ? "" : "<div class=\"articleCommentHeader\">\(headerParts.joined())</div>"

		let body = comment.bodyHTML.isEmpty ? "" : "<div class=\"articleCommentBody\">\(comment.bodyHTML)</div>"

		let repliesHTML = comment.replies.isEmpty
			? ""
			: listHTML(for: comment.replies, className: "articleCommentReplies")

		let permalinkHTML: String
		if let permalink = comment.permalink {
			let title = NSLocalizedString("View comment on the original site", comment: "Comment permalink")
			permalinkHTML = "<a class=\"articleCommentPermalink\" href=\"\(permalink.absoluteString.escapedHTML)\" title=\"\(title.escapedHTML)\">#</a>"
		} else {
			permalinkHTML = ""
		}

		return """
		<li class="articleComment" data-comment-id="\(comment.id.escapedHTML)">
		\(headerHTML)\(body)\(permalinkHTML)\(repliesHTML)
		</li>
		"""
	}

	private static func authorHTML(for comment: ArticleComment) -> String {
		let avatarHTML: String
		if let avatarURL = comment.authorAvatarURL {
			avatarHTML = "<img class=\"articleCommentAvatar\" src=\"\(avatarURL.absoluteString.escapedHTML)\" alt=\"\">"
		} else {
			avatarHTML = ""
		}

		let name = comment.authorName.isEmpty
			? NSLocalizedString("Anonymous", comment: "Comment author with no name")
			: comment.authorName

		let nameHTML: String
		if let authorURL = comment.authorURL {
			nameHTML = "<a class=\"articleCommentAuthor\" href=\"\(authorURL.absoluteString.escapedHTML)\">\(name.escapedHTML)</a>"
		} else {
			nameHTML = "<span class=\"articleCommentAuthor\">\(name.escapedHTML)</span>"
		}

		return "<div class=\"articleCommentAuthorCell\">\(avatarHTML)\(nameHTML)</div>"
	}

	private static func dateHTML(for comment: ArticleComment) -> String {
		guard let date = comment.date else { return "" }
		return "<span class=\"articleCommentDate\">\(Self.dateFormatter.string(from: date).escapedHTML)</span>"
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}()
}
