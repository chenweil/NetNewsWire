//
//  HTMLElementParser.swift
//  NetNewsWire
//
//  A small, forgiving HTML parser used by the comments providers.
//
//  It is not a spec-compliant parser and does not try to be. It only needs to
//  answer questions like “what is inside this element?” and “which elements
//  match this class name?” about arbitrary third-party pages, so it skips
//  comments, doctypes and raw-text elements, and never throws.
//

import Foundation

/// An element parsed out of an HTML document.
final class HTMLElement {

	/// Lowercased tag name, e.g. `div`.
	let name: String

	/// Lowercased attribute names mapped to their values.
	let attributes: [String: String]

	/// The element's children, in document order.
	fileprivate(set) var children: [HTMLElement] = []

	/// The element's parent, when it has one.
	weak var parent: HTMLElement?

	/// The raw HTML between the start and end tags.
	fileprivate(set) var innerHTML: String = ""

	/// The raw HTML of the element, including its tags.
	fileprivate(set) var outerHTML: String = ""

	fileprivate let openTagStart: String.Index
	fileprivate let openTagEnd: String.Index

	fileprivate init(name: String, attributes: [String: String], openTagStart: String.Index, openTagEnd: String.Index) {
		self.name = name
		self.attributes = attributes
		self.openTagStart = openTagStart
		self.openTagEnd = openTagEnd
	}

	/// Value of the given attribute, if present.
	func attribute(_ name: String) -> String? {
		attributes[name]
	}

	/// The element's class attribute split into individual tokens.
	var classTokens: [String] {
		guard let className = attributes["class"] else { return [] }
		return className
			.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
			.map(String.init)
	}

	/// Whether the element carries the given class token.
	func hasClass(_ token: String) -> Bool {
		classTokens.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame })
	}

	/// The element's text content, with all tags removed.
	var textContent: String {
		HTMLElementParser.text(fromHTML: innerHTML)
	}

	/// All descendants of this element, depth first, including nested ones.
	var descendants: [HTMLElement] {
		var result: [HTMLElement] = []
		for child in children {
			result.append(child)
			result.append(contentsOf: child.descendants)
		}
		return result
	}

	/// The first descendant matching the given predicate.
	func firstDescendant(where predicate: (HTMLElement) -> Bool) -> HTMLElement? {
		for descendant in descendants where predicate(descendant) {
			return descendant
		}
		return nil
	}

	/// All descendants matching the given predicate.
	func descendants(where predicate: (HTMLElement) -> Bool) -> [HTMLElement] {
		descendants.filter(predicate)
	}
}

/// Parses HTML documents into a tree of `HTMLElement`s.
enum HTMLElementParser {

	/// Elements that never have content or a closing tag.
	private static let voidElements: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr",
	]

	/// Elements whose content is raw text rather than markup.
	private static let rawTextElements: Set<String> = ["script", "style", "textarea", "title"]

	/// Parses `html` and returns the top-level elements.
	static func parse(_ html: String) -> [HTMLElement] {
		let tags = tokenize(html)
		return buildTree(html, tags: tags)
	}

	/// Parses `html` and returns every element in it, in document order.
	static func allElements(in html: String) -> [HTMLElement] {
		parse(html).flatMap { [$0] + $0.descendants }
	}

	/// The text of an HTML fragment: tags removed, entities decoded, and
	/// runs of whitespace collapsed.
	static func text(fromHTML html: String) -> String {
		var text = html
		if let pattern = try? NSRegularExpression(pattern: "<[^>]*>", options: [.dotMatchesLineSeparators]) {
			let range = NSRange(html.startIndex..<html.endIndex, in: html)
			text = pattern.stringByReplacingMatches(in: html, range: range, withTemplate: " ")
		}
		text = text
			.replacingOccurrences(of: "&nbsp;", with: " ")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&amp;", with: "&")
		while text.contains("  ") {
			text = text.replacingOccurrences(of: "  ", with: " ")
		}
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Tokenizer

	private struct Tag {
		let name: String
		let isClosing: Bool
		let isSelfClosing: Bool
		let attributes: [String: String]
		let start: String.Index
		let end: String.Index
	}

	private static func tokenize(_ html: String) -> [Tag] {
		var tags: [Tag] = []
		var index = html.startIndex

		while index < html.endIndex {
			guard let tagStart = html[index...].firstIndex(of: "<") else { break }
			let afterTagStart = html.index(after: tagStart)
			guard afterTagStart < html.endIndex else { break }

			let nextCharacter = html[afterTagStart]

			// Comments and doctypes: skip to the end of the declaration.
			if nextCharacter == "!" || nextCharacter == "?" {
				if html[afterTagStart...].hasPrefix("<!--") {
					guard let end = html.range(of: "-->", range: afterTagStart..<html.endIndex) else { break }
					index = end.upperBound
				} else {
					guard let end = html[afterTagStart...].firstIndex(of: ">") else { break }
					index = html.index(after: end)
				}
				continue
			}

			// Closing tag.
			if nextCharacter == "/" {
				guard let end = html[afterTagStart...].firstIndex(of: ">") else { break }
				let name = String(html[html.index(after: afterTagStart)..<end])
					.trimmingCharacters(in: .whitespacesAndNewlines)
					.lowercased()
				if !name.isEmpty {
					tags.append(Tag(name: name, isClosing: true, isSelfClosing: false, attributes: [:], start: tagStart, end: html.index(after: end)))
				}
				index = html.index(after: end)
				continue
			}

			// Opening tag.
			var cursor = afterTagStart
			while cursor < html.endIndex, html[cursor].isLetter || html[cursor].isNumber || html[cursor] == "-" || html[cursor] == "_" {
				cursor = html.index(after: cursor)
			}
			let name = String(html[afterTagStart..<cursor]).lowercased()
			guard !name.isEmpty else {
				// Not a tag — e.g. a bare “<” in prose. Move past it.
				index = html.index(after: tagStart)
				continue
			}

			var attributes: [String: String] = [:]
			var isSelfClosing = false
			var closed = false

			while cursor < html.endIndex {
				while cursor < html.endIndex, html[cursor].isWhitespace {
					cursor = html.index(after: cursor)
				}
				guard cursor < html.endIndex else { break }

				if html[cursor] == ">" {
					cursor = html.index(after: cursor)
					closed = true
					break
				}

				if html[cursor] == "/" {
					isSelfClosing = true
					cursor = html.index(after: cursor)
					continue
				}

				let attributeNameStart = cursor
				while cursor < html.endIndex, html[cursor] != "=", html[cursor] != ">", html[cursor] != "/", !html[cursor].isWhitespace {
					cursor = html.index(after: cursor)
				}
				let attributeName = String(html[attributeNameStart..<cursor]).lowercased()

				var valueCursor = cursor
				while valueCursor < html.endIndex, html[valueCursor].isWhitespace {
					valueCursor = html.index(after: valueCursor)
				}

				var value = ""
				if valueCursor < html.endIndex, html[valueCursor] == "=" {
					valueCursor = html.index(after: valueCursor)
					while valueCursor < html.endIndex, html[valueCursor].isWhitespace {
						valueCursor = html.index(after: valueCursor)
					}
					if valueCursor < html.endIndex, html[valueCursor] == "\"" || html[valueCursor] == "'" {
						let quote = html[valueCursor]
						let valueStart = html.index(after: valueCursor)
						guard let valueEnd = html[valueStart...].firstIndex(of: quote) else { break }
						value = String(html[valueStart..<valueEnd])
						cursor = html.index(after: valueEnd)
					} else {
						let valueStart = valueCursor
						while valueCursor < html.endIndex, !html[valueCursor].isWhitespace, html[valueCursor] != ">" {
							valueCursor = html.index(after: valueCursor)
						}
						value = String(html[valueStart..<valueCursor])
						cursor = valueCursor
					}
				}

				if !attributeName.isEmpty {
					attributes[attributeName] = value
				}
			}

			guard closed else { break }

			tags.append(Tag(name: name, isClosing: false, isSelfClosing: isSelfClosing, attributes: attributes, start: tagStart, end: cursor))
			index = cursor

			// Raw-text elements hold text, not markup: skip to the closing tag.
			if rawTextElements.contains(name), !isSelfClosing {
				if let closeRange = html.range(of: "</\(name)", options: [.caseInsensitive], range: index..<html.endIndex) {
					index = closeRange.lowerBound
				}
			}
		}

		return tags
	}

	// MARK: - Tree builder

	private static func buildTree(_ html: String, tags: [Tag]) -> [HTMLElement] {
		var roots: [HTMLElement] = []
		var stack: [HTMLElement] = []

		func attach(_ element: HTMLElement) {
			if let parent = stack.last {
				element.parent = parent
				parent.children.append(element)
			} else {
				roots.append(element)
			}
		}

		for tag in tags {
			if tag.isClosing {
				guard let matchIndex = stack.lastIndex(where: { $0.name == tag.name }) else { continue }
				// Elements left open above the match are closed where they opened.
				while stack.count > matchIndex + 1 {
					let element = stack.removeLast()
					finish(element, innerEnd: element.openTagEnd, outerEnd: element.openTagEnd, html: html)
					attach(element)
				}
				let element = stack.removeLast()
				finish(element, innerEnd: tag.start, outerEnd: tag.end, html: html)
				attach(element)
			} else {
				let element = HTMLElement(
					name: tag.name,
					attributes: tag.attributes,
					openTagStart: tag.start,
					openTagEnd: tag.end
				)
				if tag.isSelfClosing || voidElements.contains(tag.name) {
					finish(element, innerEnd: tag.end, outerEnd: tag.end, html: html)
					attach(element)
				} else {
					stack.append(element)
				}
			}
		}

		while let element = stack.popLast() {
			finish(element, innerEnd: element.openTagEnd, outerEnd: element.openTagEnd, html: html)
			attach(element)
		}

		return roots
	}

	private static func finish(_ element: HTMLElement, innerEnd: String.Index, outerEnd: String.Index, html: String) {
		element.innerHTML = String(html[element.openTagEnd..<innerEnd])
		element.outerHTML = String(html[element.openTagStart..<outerEnd])
	}
}
