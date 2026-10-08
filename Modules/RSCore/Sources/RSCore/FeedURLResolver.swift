//
//  FeedURLResolver.swift
//  RSCore
//

import Foundation

/// Implemented by errors thrown while retrieving a feed, so callers can tell
/// “the server said no” from “the server never answered”.
public protocol FeedRetrievalFailure: Error {

	/// The HTTP status code received, or `nil` when no response arrived.
	var httpStatusCode: Int? { get }
	var requiresBrowserVerification: Bool { get }
}

public extension FeedRetrievalFailure {
	var requiresBrowserVerification: Bool { false }
}

/// Resolves feed URLs that use an app-specific scheme instead of http(s).
///
/// The app installs one resolver during launch. Strings using a scheme that no
/// installed resolver claims are left alone by URL validation.
public protocol FeedURLResolving: Sendable {

	/// Lowercased URL schemes claimed by this resolver, e.g. `["rsshub"]`.
	var handledSchemes: Set<String> { get }

	/// Returns the http(s) URL to download the feed from.
	/// - Parameter url: A URL whose scheme is in ``handledSchemes``.
	/// - Throws: If the URL can’t be resolved.
	func resolveFeedURL(_ url: URL) throws -> URL
}

/// Registry for the app’s installed ``FeedURLResolving``.
public enum FeedURLResolver {

	private static let lock = NSLock()
	nonisolated(unsafe) private static var storage: (any FeedURLResolving)?

	/// The installed resolver, or `nil` if the app hasn’t installed one.
	public static var installed: (any FeedURLResolving)? {
		lock.withLock { storage }
	}

	/// Installs the app’s resolver. Called once during launch.
	public static func install(_ resolver: (any FeedURLResolving)?) {
		lock.withLock {
			storage = resolver
		}
	}

	/// Returns the resolver claiming the given URL’s scheme, if one is installed.
	public static func resolver(for url: URL) -> (any FeedURLResolving)? {
		guard
			let scheme = url.scheme?.lowercased(),
			let resolver = installed,
			resolver.handledSchemes.contains(scheme)
		else {
			return nil
		}
		return resolver
	}

	/// Returns `true` if the string uses a scheme claimed by the installed resolver.
	public static func claims(string: String) -> Bool {
		guard let url = URL(string: string.trimmingWhitespace) else { return false }
		return resolver(for: url) != nil
	}

	/// Resolves app-specific feed URL schemes, leaving every other URL untouched.
	/// - Throws: If the string uses a claimed scheme but can’t be resolved.
	public static func resolve(_ urlString: String) throws -> String {
		guard
			let url = URL(string: urlString.trimmingWhitespace),
			let resolver = resolver(for: url)
		else {
			return urlString
		}
		return try resolver.resolveFeedURL(url).absoluteString
	}
}
