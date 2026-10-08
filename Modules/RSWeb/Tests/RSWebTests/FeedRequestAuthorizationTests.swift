import Foundation
import Testing
import os
@testable import RSWeb

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct FeedRequestAuthorizationTests {
	private func context(_ identifier: String, authorized: Bool = true) throws -> FeedRequestContext {
		FeedRequestContext(instanceURL: try #require(URL(string: "https://rss.example/hub")), cacheIdentifier: identifier,
			cookieHeader: authorized ? "cf_clearance=fixture" : nil,
			userAgent: authorized ? "Fixture Browser" : nil, accessKey: authorized ? "fixture-key" : nil)
	}

	@Test func credentialsStayWithinTheInstanceOnRedirects() throws {
		let context = try context("verified")
		let originalURL = try #require(URL(string: "https://rss.example/hub/caixin/latest?format=atom"))
		let authorized = context.prepare(URLRequest(url: originalURL))
		#expect(authorized.value(forHTTPHeaderField: "Cookie") == "cf_clearance=fixture")
		#expect(authorized.url?.absoluteString.contains("key=fixture-key") == true)
		#expect(originalURL.absoluteString.contains("key=") == false)
		#expect(context.subscriptionURL(for: try #require(authorized.url)) == originalURL)
		for destination in ["https://other.example/hub/feed?key=fixture-key", "http://rss.example/hub/feed", "https://rss.example:444/hub/feed", "https://rss.example/hub-other/feed", "https://rss.example/other/feed"] {
			var redirect = authorized
			redirect.url = URL(string: destination)
			let result = context.prepareRedirect(redirect)
			#expect(result.value(forHTTPHeaderField: "Cookie") == nil)
			#expect(result.value(forHTTPHeaderField: "User-Agent") == nil)
			#expect(result.url?.absoluteString.contains("fixture-key") == false)
		}
		var sameInstance = authorized
		sameInstance.url = URL(string: "https://rss.example/hub/new-feed")
		let redirected = context.prepareRedirect(sameInstance)
		#expect(redirected.value(forHTTPHeaderField: "Cookie") == "cf_clearance=fixture")
		#expect(redirected.url?.absoluteString.contains("key=fixture-key") == true)
	}

	@Test func subscriptionDownloadRetriesCached403AfterVerification() async throws {
		AuthorizationFixture.reset()
		let provider = FixtureAuthorizer(context: try context("unverified", authorized: false))
		FeedRequestAuthorization.provider = provider
		defer { FeedRequestAuthorization.provider = nil }
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [AuthorizationFixture.self]
		let downloader = Downloader(sessionConfiguration: configuration)
		let url = try #require(URL(string: "https://rss.example/hub/caixin/latest"))
		let denied = try await downloader.download(url)
		#expect(denied.response?.forcedStatusCode == 403)
		let cachedDenial = try await downloader.download(url)
		#expect(cachedDenial.returnedFromCache)
		#expect(AuthorizationFixture.requestCount == 1)
		provider.currentContext = try context("verified")
		let success = try await downloader.download(url)
		#expect(success.response?.forcedStatusCode == 200)
		#expect(!success.returnedFromCache)
		#expect(AuthorizationFixture.requestCount == 2)
	}

	@Test func refreshRetriesSuppressed403AfterVerification() async throws {
		AuthorizationFixture.reset()
		let provider = FixtureAuthorizer(context: try context("unverified", authorized: false))
		FeedRequestAuthorization.provider = provider
		defer { FeedRequestAuthorization.provider = nil }
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [AuthorizationFixture.self]
		let delegate = FixtureDownloadDelegate()
		let session = DownloadSession(delegate: delegate, sessionConfiguration: configuration)
		let url = try #require(URL(string: "https://rss.example/hub/caixin/latest"))
		await delegate.download(url, using: session)
		#expect(delegate.statuses == [403])
		await delegate.download(url, using: session)
		#expect(delegate.skipped == 1)
		#expect(AuthorizationFixture.requestCount == 1)
		provider.currentContext = try context("verified")
		await delegate.download(url, using: session)
		#expect(delegate.completedStatuses == [200])
		#expect(AuthorizationFixture.requestCount == 2)
	}

	@Test func challengeHTMLIsReportedEvenWithHTTP200() async throws {
		AuthorizationFixture.reset(challenge: true)
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [AuthorizationFixture.self]
		let delegate = FixtureDownloadDelegate()
		let session = DownloadSession(delegate: delegate, sessionConfiguration: configuration)
		await delegate.download(try #require(URL(string: "https://rss.example/hub/caixin/latest")), using: session)
		#expect(delegate.needsVerification)
		#expect(delegate.completedStatuses.isEmpty)
	}
}

@MainActor private final class FixtureAuthorizer: FeedRequestAuthorizing {
	var currentContext: FeedRequestContext
	init(context: FeedRequestContext) { currentContext = context }
	func context(for url: URL) -> FeedRequestContext? { currentContext.contains(url) ? currentContext : nil }
}

private final class AuthorizationFixture: URLProtocol, @unchecked Sendable {
	private struct State { var requests = 0; var challenge = false }
	private static let state = OSAllocatedUnfairLock(initialState: State())
	static var requestCount: Int { state.withLock { $0.requests } }
	static func reset(challenge: Bool = false) { state.withLock { $0 = State(challenge: challenge) } }
	override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "rss.example" }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
	override func startLoading() {
		let challenge = Self.state.withLock { state in state.requests += 1; return state.challenge }
		let authorized = request.value(forHTTPHeaderField: "Cookie") == "cf_clearance=fixture"
			&& request.value(forHTTPHeaderField: "User-Agent") == "Fixture Browser"
			&& request.url?.query?.contains("key=fixture-key") == true
		let status = challenge || authorized ? 200 : 403
		let headers = challenge ? ["cf-mitigated": "challenge", "Content-Type": "text/html"] : ["Content-Type": "application/rss+xml"]
		guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
			client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
			return
		}
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: Data((challenge ? "<html>Verify you are human</html>" : "<rss version=\"2.0\"><channel><title>Fixture</title></channel></rss>").utf8))
		client?.urlProtocolDidFinishLoading(self)
	}
	override func stopLoading() {}
}

@MainActor private final class FixtureDownloadDelegate: DownloadSessionDelegate {
	var statuses = [Int]()
	var completedStatuses = [Int]()
	var skipped = 0
	var needsVerification = false
	private var continuation: CheckedContinuation<Void, Never>?
	func download(_ url: URL, using session: DownloadSession) async {
		await withCheckedContinuation { continuation in
			self.continuation = continuation
			session.download([url])
		}
	}
	func downloadSession(_ downloadSession: DownloadSession, conditionalGetInfoFor url: URL) -> HTTPConditionalGetInfo? { nil }
	func downloadSession(_ downloadSession: DownloadSession, didReceiveResponse url: URL) {}
	func downloadSession(_ downloadSession: DownloadSession, didSkip url: URL, reason: String) { skipped += 1 }
	func downloadSession(_ downloadSession: DownloadSession, downloadDidComplete url: URL, response: URLResponse?, data: Data, error: NSError?) { completedStatuses.append(response?.forcedStatusCode ?? 0) }
	func downloadSession(_ downloadSession: DownloadSession, shouldContinueAfterReceivingData data: Data, url: URL) -> Bool { true }
	func downloadSession(_ downloadSession: DownloadSession, httpError statusCode: Int, url: URL) { statuses.append(statusCode) }
	func downloadSession(_ downloadSession: DownloadSession, requiresBrowserVerification url: URL) { needsVerification = true }
	func downloadSession(_ downloadSession: DownloadSession, didFollowRedirectFor url: URL, from fromURL: URL, to toURL: URL, statusCode: Int) {}
	func downloadSessionDidComplete(_ downloadSession: DownloadSession) {
		continuation?.resume()
		continuation = nil
	}
}
