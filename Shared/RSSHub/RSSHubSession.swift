import Foundation
import WebKit
import RSWeb
import RSParser

/// Owns the local browser session. Neither cookies nor access keys become feed IDs.
@MainActor final class RSSHubSession: FeedRequestAuthorizing {
	static let shared = RSSHubSession()

	// Dedicated store: article web views and RSSHub verification do not share cookies.
	let websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuid: (0x65, 0x21, 0xA2, 0x30, 0x31, 0x45, 0x4D, 0xAB, 0xB4, 0xC5, 0x99, 0x67, 0x8A, 0x15, 0xBC, 0xD1)))
	private let settings = RSSHubSettings.shared
	private var cookies = [HTTPCookie]()
	private var userAgent: String?
	private var instance: String?
	private var accessKey: String?
	private var generation = UUID().uuidString

	func context(for url: URL) -> FeedRequestContext? {
		guard let baseURL = settings.baseURL else {
			return nil
		}
		let key = settings.accessKey
		if instance != settings.baseURLString || accessKey != key {
			if instance != settings.baseURLString {
				cookies = []
				userAgent = nil
			}
			instance = settings.baseURLString
			accessKey = key
			generation = UUID().uuidString
		}
		let context = makeContext(baseURL: baseURL, cookies: cookies, userAgent: userAgent, key: key)
		return context.contains(url) ? context : nil
	}

	func restore() async {
		let base = settings.baseURLString
		guard UserDefaults.standard.string(forKey: "rsshub.session.instance") == base,
			let savedAgent = UserDefaults.standard.string(forKey: "rsshub.session.userAgent") else {
			return
		}
		let savedCookies = await websiteDataStore.httpCookieStore.allCookies()
		guard settings.baseURLString == base else {
			return
		}
		instance = base
		accessKey = settings.accessKey
		cookies = savedCookies
		userAgent = savedAgent
		generation = UUID().uuidString
	}

	/// Probe the actual feed using URLSession before accepting browser credentials.
	/// The presence of a clearance cookie alone is not proof of compatibility.
	func verify(feedURL: URL, browserUserAgent: String) async throws {
		guard let baseURL = settings.baseURL else {
			throw RSSHubError.invalidInstance
		}
		let base = settings.baseURLString
		let key = settings.accessKey
		let candidateCookies = await websiteDataStore.httpCookieStore.allCookies()
		let candidate = makeContext(baseURL: baseURL, cookies: candidateCookies, userAgent: browserUserAgent, key: key)
		guard candidate.contains(feedURL) else {
			throw RSSHubError.invalidInstance
		}
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieStorage = nil
		configuration.timeoutIntervalForRequest = 20
		let delegate = RSSHubProbeRedirectDelegate(context: candidate)
		let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
		defer { session.invalidateAndCancel() }
		let (data, response) = try await session.data(for: candidate.prepare(URLRequest(url: feedURL)))
		let httpResponse = response as? HTTPURLResponse
		if httpResponse?.value(forHTTPHeaderField: "cf-mitigated") == "challenge" {
			throw RSSHubError.browserVerificationRequired(statusCode: httpResponse?.statusCode)
		}
		guard let status = httpResponse?.statusCode, (200..<300).contains(status) else {
			let code = httpResponse?.statusCode
			switch code ?? 0 {
			case 401, 403: throw RSSHubError.accessDenied(statusCode: code)
			case 404: throw RSSHubError.routeNotFound(statusCode: code)
			case 429: throw RSSHubError.rateLimited(statusCode: code)
			case 500...599: throw RSSHubError.serverError(statusCode: code)
			default: throw RSSHubError.unreachable(statusCode: code)
			}
		}
		guard let _ = try await FeedParser.parse(ParserData(url: feedURL.absoluteString, data: data)) else {
			throw RSSHubError.unreachable(statusCode: httpResponse?.statusCode)
		}
		guard settings.baseURLString == base, settings.accessKey == key else {
			throw RSSHubError.invalidInstance
		}
		try Task.checkCancellation()
		instance = base
		accessKey = key
		cookies = candidateCookies
		userAgent = browserUserAgent
		generation = UUID().uuidString
		UserDefaults.standard.set(base, forKey: "rsshub.session.instance")
		UserDefaults.standard.set(browserUserAgent, forKey: "rsshub.session.userAgent")
	}

	private func makeContext(baseURL: URL, cookies: [HTTPCookie], userAgent: String?, key: String?) -> FeedRequestContext {
		let host = baseURL.host?.lowercased() ?? ""
		let usableCookies = cookies.filter { cookie in
			let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
			let domainMatches = host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain))
			// Cloudflare's session cookies are root-scoped. Do not widen a narrower cookie's path.
			return domainMatches && cookie.path == "/" && (cookie.expiresDate.map { $0 > Date() } ?? true)
				&& (!cookie.isSecure || baseURL.scheme == "https")
		}
		let cookieHeader = usableCookies.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: usableCookies)["Cookie"]
		return FeedRequestContext(instanceURL: baseURL, cacheIdentifier: generation, cookieHeader: cookieHeader, userAgent: userAgent, accessKey: key)
	}
}

private final class RSSHubProbeRedirectDelegate: NSObject, URLSessionTaskDelegate {
	let context: FeedRequestContext

	init(context: FeedRequestContext) {
		self.context = context
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		// Verification must retrieve this instance's feed, not a redirected login page.
		guard let url = request.url, context.contains(url) else {
			completionHandler(nil)
			return
		}
		completionHandler(context.prepareRedirect(request))
	}
}
