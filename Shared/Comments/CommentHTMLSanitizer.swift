//
//  CommentHTMLSanitizer.swift
//  NetNewsWire
//
//  Makes comment HTML safe to inject into the article view.
//

import Foundation

/// Strips the parts of third-party comment HTML that must not end up in the
/// article web view: scripts, styles, event handlers and `javascript:` URLs.
enum CommentHTMLSanitizer {

	/// Returns `html` with script-like content removed.
	static func sanitized(_ html: String) -> String {
		guard !html.isEmpty else { return html }

		var result = removingElements(named: "script", from: html)
		result = removingElements(named: "style", from: result)
		result = removingEventHandlerAttributes(from: result)
		result = removingJavaScriptURLs(from: result)
		return result
	}

	/// Removes `<name>…</name>` blocks, including their content.
	private static func removingElements(named name: String, from html: String) -> String {
		guard let pattern = try? NSRegularExpression(
			pattern: "<\(name)\\b[^>]*>.*?</\(name)\\s*>",
			options: [.caseInsensitive, .dotMatchesLineSeparators]
		) else {
			return html
		}
		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		return pattern.stringByReplacingMatches(in: html, range: range, withTemplate: "")
	}

	/// Removes `onclick="…"`-style attributes.
	private static func removingEventHandlerAttributes(from html: String) -> String {
		guard let pattern = try? NSRegularExpression(
			pattern: "\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
			options: [.caseInsensitive]
		) else {
			return html
		}
		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		return pattern.stringByReplacingMatches(in: html, range: range, withTemplate: "")
	}

	/// Replaces `javascript:` URLs with an empty value.
	private static func removingJavaScriptURLs(from html: String) -> String {
		guard let pattern = try? NSRegularExpression(
			pattern: "(href|src)\\s*=\\s*(\"|')\\s*javascript:[^\"']*\\2",
			options: [.caseInsensitive]
		) else {
			return html
		}
		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		return pattern.stringByReplacingMatches(in: html, range: range, withTemplate: "$1=$2$2")
	}
}
