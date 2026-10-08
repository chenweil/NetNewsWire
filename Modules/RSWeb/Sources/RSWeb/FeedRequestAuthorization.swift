import Foundation

/// Per-request credentials, kept separate from the URL identifying a subscription.
public struct FeedRequestContext: Sendable {
	public let instanceURL: URL
	public let cacheIdentifier: String
	private let cookieHeader: String?
	private let userAgent: String?
	private let accessKey: String?

	public init(instanceURL: URL, cacheIdentifier: String, cookieHeader: String? = nil, userAgent: String? = nil, accessKey: String? = nil) {
		self.instanceURL = instanceURL
		self.cacheIdentifier = cacheIdentifier
		self.cookieHeader = cookieHeader
		self.userAgent = userAgent
		self.accessKey = accessKey
	}

	public func contains(_ url: URL) -> Bool {
		guard url.scheme?.lowercased() == instanceURL.scheme?.lowercased(),
			url.host?.lowercased() == instanceURL.host?.lowercased(),
			Self.port(url) == Self.port(instanceURL) else {
			return false
		}
		let prefix = instanceURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		return prefix.isEmpty || url.path == "/" + prefix || url.path.hasPrefix("/" + prefix + "/")
	}

	public func prepare(_ request: URLRequest) -> URLRequest {
		guard let url = request.url, contains(url) else {
			return request
		}
		var result = request
		if let cookieHeader { result.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
		if let userAgent { result.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
		if let accessKey, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			var items = components.queryItems ?? []
			items.removeAll { $0.name == "key" }
			items.append(URLQueryItem(name: "key", value: accessKey))
			components.queryItems = items
			result.url = components.url
		}
		return result
	}

	/// URLSession can carry headers forward on redirects. Strip our credentials
	/// before deciding whether the new destination is inside the instance.
	public func prepareRedirect(_ request: URLRequest) -> URLRequest {
		var result = request
		if cookieHeader != nil { result.setValue(nil, forHTTPHeaderField: "Cookie") }
		if userAgent != nil { result.setValue(nil, forHTTPHeaderField: "User-Agent") }
		if let accessKey, let url = result.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			let items = (components.queryItems ?? []).filter { !($0.name == "key" && $0.value == accessKey) }
			components.queryItems = items.isEmpty ? nil : items
			result.url = components.url
		}
		return prepare(result)
	}

	public func subscriptionURL(for url: URL) -> URL {
		guard let accessKey, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url
		}
		let items = (components.queryItems ?? []).filter { !($0.name == "key" && $0.value == accessKey) }
		components.queryItems = items.isEmpty ? nil : items
		return components.url ?? url
	}

	private static func port(_ url: URL) -> Int? {
		url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
	}
}

@MainActor public protocol FeedRequestAuthorizing: AnyObject {
	func context(for url: URL) -> FeedRequestContext?
}

/// Installed by the app; RSWeb has no dependency on preferences or WebKit.
@MainActor public enum FeedRequestAuthorization {
	public static var provider: (any FeedRequestAuthorizing)?

	public static func context(for url: URL) -> FeedRequestContext? {
		provider?.context(for: url)
	}
}
