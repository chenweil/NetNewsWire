//
//  RSSHubResolver.swift
//  NetNewsWire
//

import Foundation
import RSCore

/// Expands `rsshub://` URLs against the instance configured in Preferences.
///
/// `rsshub://telegram/channel/zaihuanews` with an instance of
/// `https://rsshub.app` becomes `https://rsshub.app/telegram/channel/zaihuanews`.
/// The scheme isn’t defined by RSSHub itself — it’s a convention among
/// self-hosted readers (Folo, feedoverflow, Livo).
public struct RSSHubResolver: FeedURLResolving {

	public static let scheme = "rsshub"

	private let settings: RSSHubSettings

	public init(settings: RSSHubSettings = .shared) {
		self.settings = settings
	}

	public var handledSchemes: Set<String> {
		[Self.scheme]
	}

	public func resolveFeedURL(_ url: URL) throws -> URL {
		guard
			let baseURL = settings.baseURL,
			var baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
		else {
			throw RSSHubError.invalidInstance
		}

		let parts = try Self.parts(of: url)

		guard !parts.route.isEmpty else {
			throw RSSHubError.invalidRoute
		}

		var percentEncodedBasePath = baseComponents.percentEncodedPath
		while percentEncodedBasePath.hasSuffix("/") {
			percentEncodedBasePath.removeLast()
		}
		baseComponents.percentEncodedPath = percentEncodedBasePath.isEmpty
			? "/\(parts.route)"
			: "\(percentEncodedBasePath)/\(parts.route)"

		// Access keys are intentionally not injected here. This resolver’s
		// output is the URL that gets saved as the subscription, so appending
		// a key would bake it into stored subscriptions, log messages, and
		// OPML exports. RSSHubSession supplies per-request credentials to the
		// macOS feed-fetching path instead.
		baseComponents.percentEncodedQuery = parts.query.isEmpty ? nil : parts.query

		baseComponents.percentEncodedFragment = parts.fragment.isEmpty ? nil : parts.fragment

		guard let resolvedURL = baseComponents.url else {
			throw RSSHubError.invalidInstance
		}

		return resolvedURL
	}
}

public extension RSSHubResolver {

	/// Returns the URL that a `rsshub://` string expands to, or `nil` when the
	/// string isn’t an RSSHub URL or can’t be resolved.
	func resolvedURL(for urlString: String) -> URL? {
		guard let url = URL(string: urlString.trimmingWhitespace) else { return nil }
		guard url.scheme?.lowercased() == Self.scheme else { return nil }
		return try? resolveFeedURL(url)
	}
}

private extension RSSHubResolver {

	/// The percent-encoded route, query, and fragment of a `rsshub://` URL.
	/// Everything stays percent-encoded so route params survive the round trip.
	struct Parts {
		var route = ""
		var query = ""
		var fragment = ""
	}

	/// Splits a parsed URL into route, query, and fragment via `URLComponents`
	/// instead of cutting the raw string at `?` and `#`. Manual splitting puts
	/// the query into the route whenever a fragment follows it
	/// (`rsshub://a/b?x=1#f` became route `a/b?x=1`), and assigning the mangled
	/// route to `URLComponents.percentEncodedPath` then traps — characters like
	/// `?` and `&` aren’t valid in a percent-encoded path.
	static func parts(of url: URL) throws -> Parts {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			throw RSSHubError.invalidRoute
		}

		// A hierarchical URL puts the first route segment in the host:
		// `rsshub://telegram/channel/zaihuanews` parses as host `telegram` with
		// path `/channel/zaihuanews`. The empty-host form
		// `rsshub:///telegram/channel/zaihuanews` keeps the whole route in the
		// path. Leading slashes come from either form and are dropped.
		var route = (components.percentEncodedHost ?? "") + components.percentEncodedPath
		while route.hasPrefix("/") {
			route.removeFirst()
		}

		let query = components.percentEncodedQuery ?? ""
		let fragment = components.percentEncodedFragment ?? ""

		guard
			Self.hasValidPercentEncoding(route),
			Self.hasValidPercentEncoding(query),
			Self.hasValidPercentEncoding(fragment)
		else {
			// Malformed `%` sequences would make the `percentEncoded*` setters
			// below trap instead of returning an error.
			throw RSSHubError.invalidRoute
		}

		return Parts(route: route, query: query, fragment: fragment)
	}

	/// Whether every `%` in the string starts a valid two-hex-digit escape.
	static func hasValidPercentEncoding(_ string: String) -> Bool {
		let hexDigits = "0123456789ABCDEFabcdef"
		var index = string.startIndex
		while let percentIndex = string[index...].firstIndex(of: "%") {
			let firstHexIndex = string.index(after: percentIndex)
			let secondHexIndex = string.index(after: firstHexIndex)
			guard secondHexIndex < string.endIndex else { return false }
			guard hexDigits.contains(string[firstHexIndex]), hexDigits.contains(string[secondHexIndex]) else { return false }
			index = string.index(after: secondHexIndex)
		}
		return true
	}

}
