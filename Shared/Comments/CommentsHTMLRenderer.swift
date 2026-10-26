//
//  CommentsHTMLRenderer.swift
//  NetNewsWire
//
//  Renders a comment thread as HTML for the article view.
//

import Foundation
import RSWeb

/// Renders comment threads into the HTML shown below an article.
///
/// The thread is laid out like a transcript: every comment carries its
/// position in the thread in a numbered gutter, and the metadata of a
/// comment — who said it and when — sits on one line above its body.
enum CommentsHTMLRenderer {

	/// Renders the thread, or an empty string when there is nothing to show.
	static func html(for comments: [ArticleComment], sourceName: String) -> String {
		guard !comments.isEmpty else { return "" }

		let count = comments.reduce(0) { $0 + $1.totalCount }
		let heading = NSLocalizedString("Comments", comment: "Comment thread heading")

		var ordinal = 0
		let listHTML = listHTML(for: comments, className: "articleCommentList", ordinal: &ordinal)

		// The thread carries the article's text size, so that the comments
		// grow and shrink with the article body instead of keeping a size
		// of their own.
		return """
		<div class="articleCommentsSize \(Self.articleSizeClass)">
		<section class="articleComments" data-comments-source="\(sourceName.escapedHTML)">
		<header class="articleCommentsHeader">
		<h2 class="articleCommentsHeading"><span class="articleCommentsLabel">\(heading.escapedHTML)</span><span class="articleCommentsCount">\(count)</span></h2>
		<span class="articleCommentsSource">\(sourceName.escapedHTML)</span>
		</header>
		\(listHTML)
		</section>
		</div>
		"""
	}

	/// The article text size class, which the theme turns into a font size.
	private static var articleSizeClass: String {
		#if os(macOS)
		return AppDefaults.articleTextSize.cssClass
		#else
		return ""
		#endif
	}

	// MARK: - Private

	private static func listHTML(for comments: [ArticleComment], className: String, ordinal: inout Int) -> String {
		var items = ""
		for comment in comments {
			items += itemHTML(for: comment, ordinal: &ordinal)
		}
		return "<ol class=\"\(className)\">\(items)</ol>"
	}

	private static func itemHTML(for comment: ArticleComment, ordinal: inout Int) -> String {
		ordinal += 1
		let number = ordinal

		let ordinalHTML: String
		if let permalink = comment.permalink {
			let title = NSLocalizedString("View comment on the original site", comment: "Comment permalink")
			ordinalHTML = "<a class=\"articleCommentOrdinal\" href=\"\(permalink.absoluteString.escapedHTML)\" title=\"\(title.escapedHTML)\">\(number)</a>"
		} else {
			ordinalHTML = "<span class=\"articleCommentOrdinal\">\(number)</span>"
		}

		let repliesHTML = comment.replies.isEmpty
			? ""
			: listHTML(for: comment.replies, className: "articleCommentReplies", ordinal: &ordinal)

		let bodyHTML = comment.bodyHTML.isEmpty
			? ""
			: "<div class=\"articleCommentBody\">\(comment.bodyHTML)</div>"

		return """
		<li class="articleComment" data-comment-id="\(comment.id.escapedHTML)">
		\(ordinalHTML)
		<div class="articleCommentContent">
		\(avatarHTML(for: comment))
		<div class="articleCommentHead">\(authorHTML(for: comment))\(dateHTML(for: comment))</div>
		\(bodyHTML)
		\(repliesHTML)
		</div>
		</li>
		"""
	}

	/// The author's picture, or a monogram when the source has none.
	private static func avatarHTML(for comment: ArticleComment) -> String {
		if let avatarURL = comment.authorAvatarURL {
			return "<img class=\"articleCommentAvatar\" src=\"\(avatarURL.absoluteString.escapedHTML)\" alt=\"\">"
		}

		let monogram = monogram(for: comment.authorName)
		guard !monogram.isEmpty else { return "" }
		return "<span class=\"articleCommentMonogram\" aria-hidden=\"true\">\(monogram.escapedHTML)</span>"
	}

	private static func authorHTML(for comment: ArticleComment) -> String {
		let name = comment.authorName.isEmpty
			? NSLocalizedString("Anonymous", comment: "Comment author with no name")
			: comment.authorName

		if let authorURL = comment.authorURL {
			return "<a class=\"articleCommentAuthor\" href=\"\(authorURL.absoluteString.escapedHTML)\">\(name.escapedHTML)</a>"
		}
		return "<span class=\"articleCommentAuthor\">\(name.escapedHTML)</span>"
	}

	private static func dateHTML(for comment: ArticleComment) -> String {
		guard let date = comment.date else { return "" }
		let text = Self.dateFormatter.string(from: date).escapedHTML
		let machineReadable = Self.isoFormatter.format(date)
		return "<time class=\"articleCommentDate\" datetime=\"\(machineReadable)\">\(text)</time>"
	}

	/// The first character of the author's name, for use as a fallback avatar.
	private static func monogram(for name: String) -> String {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let first = trimmed.first else { return "" }
		return String(first).uppercased()
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}()

	private static let isoFormatter = Date.ISO8601FormatStyle(timeZone: .current)
}
