//
//  RSSHubSettingsTests.swift
//  NetNewsWireTests
//

import Foundation
import RSCore
import Testing
@testable import NetNewsWire

@Suite struct RSSHubSettingsTests {

	private func makeSettings() -> (RSSHubSettings, UserDefaults) {
		let defaults = UserDefaults(suiteName: "rsshub-tests-\(UUID().uuidString)")!
		return (RSSHubSettings(defaults: defaults), defaults)
	}

	@Test("base URL defaults to the official demo instance")
	func baseURLDefaults() {
		let (settings, _) = makeSettings()
		#expect(settings.baseURLString == "https://rsshub.app")
	}

	@Test("base URL falls back to the default when the stored value is unparseable")
	func baseURLFallsBackOnGarbage() {
		let (settings, defaults) = makeSettings()
		defaults.set("not a url at all", forKey: "rsshub.baseURL")
		#expect(settings.baseURLString == "https://rsshub.app")
	}

	@Test("base URL normalization adds a scheme and drops the trailing slash")
	func baseURLNormalization() {
		#expect(RSSHubSettings.normalizeBaseURLString("rsshub.example.com") == "https://rsshub.example.com")
		#expect(RSSHubSettings.normalizeBaseURLString("rsshub.example.com/") == "https://rsshub.example.com")
		#expect(RSSHubSettings.normalizeBaseURLString("https://rsshub.example.com//") == "https://rsshub.example.com")
		#expect(RSSHubSettings.normalizeBaseURLString("http://192.168.1.10:1200") == "http://192.168.1.10:1200")
		#expect(RSSHubSettings.normalizeBaseURLString("  https://rsshub.example.com  ") == "https://rsshub.example.com")
	}

	@Test("base URL normalization preserves a subpath prefix")
	func baseURLNormalizationKeepsSubpath() {
		#expect(RSSHubSettings.normalizeBaseURLString("https://example.com/rsshub") == "https://example.com/rsshub")
		#expect(RSSHubSettings.normalizeBaseURLString("https://example.com/rsshub/") == "https://example.com/rsshub")
	}

	@Test("base URL normalization rejects non-http schemes and empty input")
	func baseURLNormalizationRejectsBadInput() {
		#expect(RSSHubSettings.normalizeBaseURLString("") == nil)
		#expect(RSSHubSettings.normalizeBaseURLString("   ") == nil)
		#expect(RSSHubSettings.normalizeBaseURLString("ftp://example.com") == nil)
		#expect(RSSHubSettings.normalizeBaseURLString("rsshub://telegram/channel/foo") == nil)
	}

	@Test("base URL normalization accepts a bare host and port")
	func baseURLNormalizationAcceptsHostAndPort() {
		#expect(RSSHubSettings.normalizeBaseURLString("localhost:1200") == "https://localhost:1200")
		#expect(RSSHubSettings.normalizeBaseURLString("192.168.1.10:1200") == "https://192.168.1.10:1200")
	}

	@Test("setBaseURLString stores the normalized value")
	func setBaseURLString() {
		let (settings, _) = makeSettings()
		#expect(settings.setBaseURLString("rsshub.example.com/") == "https://rsshub.example.com")
		#expect(settings.baseURLString == "https://rsshub.example.com")
	}

	@Test("setBaseURLString refuses to store an invalid address")
	func setBaseURLStringRejectsInvalid() {
		let (settings, _) = makeSettings()
		#expect(settings.setBaseURLString("ftp://example.com") == nil)
		#expect(settings.baseURLString == "https://rsshub.app")
	}

	@Test("resetBaseURL restores the default")
	func resetBaseURL() {
		let (settings, _) = makeSettings()
		settings.setBaseURLString("rsshub.example.com")
		settings.resetBaseURL()
		#expect(settings.baseURLString == "https://rsshub.app")
	}

	@Test("health check URL points at /healthz")
	func healthCheckURL() {
		let (settings, _) = makeSettings()
		#expect(settings.healthCheckURL.absoluteString == "https://rsshub.app/healthz")
	}
}

@Suite struct RSSHubResolverTests {

	private func makeResolver(baseURL: String) -> RSSHubResolver {
		let defaults = UserDefaults(suiteName: "rsshub-resolver-tests-\(UUID().uuidString)")!
		defaults.set(baseURL, forKey: "rsshub.baseURL")
		return RSSHubResolver(settings: RSSHubSettings(defaults: defaults))
	}

	private func resolve(_ resolver: RSSHubResolver, _ urlString: String) throws -> String {
		let url = URL(string: urlString.trimmingWhitespace)!
		return try resolver.resolveFeedURL(url).absoluteString
	}

	@Test("expands a route against the configured instance")
	func expandsRoute() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub://telegram/channel/zaihuanews") == "https://rsshub.app/telegram/channel/zaihuanews")
	}

	@Test("expands against a self-hosted instance on plain http")
	func expandsPlainHTTPInstance() throws {
		let resolver = makeResolver(baseURL: "http://192.168.1.10:1200")
		#expect(try resolve(resolver, "rsshub://telegram/channel/zaihuanews") == "http://192.168.1.10:1200/telegram/channel/zaihuanews")
	}

	@Test("preserves an instance subpath prefix")
	func expandsSubpathInstance() throws {
		let resolver = makeResolver(baseURL: "https://example.com/rsshub")
		#expect(try resolve(resolver, "rsshub://telegram/channel/zaihuanews") == "https://example.com/rsshub/telegram/channel/zaihuanews")
	}

	@Test("passes query parameters through, still percent-encoded")
	func preservesQuery() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		let url = try resolve(resolver, "rsshub://telegram/channel/zaihuanews/searchQuery=a%20b?format=atom")
		#expect(url == "https://rsshub.app/telegram/channel/zaihuanews/searchQuery=a%20b?format=atom")
	}

	@Test("resolves an empty-host form")
	func resolvesEmptyHostForm() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub:///telegram/channel/zaihuanews") == "https://rsshub.app/telegram/channel/zaihuanews")
	}

	@Test("expands the mittrchina hot route")
	func expandsMittrHot() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub://mittrchina/hot") == "https://rsshub.app/mittrchina/hot")
	}

	@Test("keeps a format=atom query")
	func keepsAtomFormat() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub://mittrchina/hot?format=atom") == "https://rsshub.app/mittrchina/hot?format=atom")
	}

	@Test("keeps both a query and a fragment")
	func keepsQueryAndFragment() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub://mittrchina/hot?format=atom&page=2#section") == "https://rsshub.app/mittrchina/hot?format=atom&page=2#section")
	}

	@Test("keeps a fragment without a query")
	func keepsFragmentOnly() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(try resolve(resolver, "rsshub://mittrchina/hot#section") == "https://rsshub.app/mittrchina/hot#section")
	}

	@Test("preserves percent-encoding in the query and fragment")
	func preservesEncoding() throws {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		let resolved = try resolve(resolver, "rsshub://mittrchina/hot?query=%E4%B8%AD%E6%96%87&id=a%2Bb#frag%20one")
		#expect(resolved == "https://rsshub.app/mittrchina/hot?query=%E4%B8%AD%E6%96%87&id=a%2Bb#frag%20one")
	}

	@Test("accepts an uppercase scheme")
	func acceptsUppercaseScheme() {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(resolver.resolvedURL(for: "RSSHub://mittrchina/hot")?.absoluteString == "https://rsshub.app/mittrchina/hot")
		#expect(resolver.resolvedURL(for: "RSSHUB://mittrchina/hot")?.absoluteString == "https://rsshub.app/mittrchina/hot")
	}

	@Test("returns an error instead of crashing on empty routes")
	func emptyRoutesThrow() {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		for urlString in ["rsshub://", "rsshub:///", "rsshub://?format=atom", "rsshub://#section", "rsshub://   "] {
			#expect(throws: RSSHubError.self) {
				_ = try resolver.resolveFeedURL(URL(string: urlString) ?? URL(fileURLWithPath: "/"))
			}
			#expect(resolver.resolvedURL(for: urlString) == nil)
		}
	}

	@Test("throws when there is no route")
	func throwsWithoutRoute() {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		let url = URL(string: "rsshub://")!
		#expect(throws: RSSHubError.self) {
			try resolver.resolveFeedURL(url)
		}
	}

	@Test("resolvedURL returns nil for non-rsshub URLs")
	func resolvedURLRejectsOtherSchemes() {
		let resolver = makeResolver(baseURL: "https://rsshub.app")
		#expect(resolver.resolvedURL(for: "https://daringfireball.net/feed") == nil)
		#expect(resolver.resolvedURL(for: "feed:daringfireball.net") == nil)
		#expect(resolver.resolvedURL(for: "rsshub://") == nil)
		#expect(resolver.resolvedURL(for: "rsshub://telegram/channel/zaihuanews")?.absoluteString == "https://rsshub.app/telegram/channel/zaihuanews")
	}

	@Test("ownsURL matches only the configured instance host")
	func ownsURL() {
		let settings = RSSHubSettings(defaults: UserDefaults(suiteName: "rsshub-owns-\(UUID().uuidString)")!)
		settings.setBaseURLString("https://rsshub.app")
		#expect(RSSHubError.ownsURL(URL(string: "https://rsshub.app/telegram/channel/foo"), settings: settings))
		#expect(RSSHubError.ownsURL(URL(string: "https://daringfireball.net/feed"), settings: settings) == false)
		#expect(RSSHubError.ownsURL(nil, settings: settings) == false)
	}
}

@Suite struct RSSHubErrorTests {

	/// Stand-in for retrieval errors thrown while fetching a feed.
	private struct StubRetrievalFailure: FeedRetrievalFailure {
		let httpStatusCode: Int?
		var requiresBrowserVerification = false
	}

	@Test("challenge responses remain distinguishable from ordinary access denial")
	func mapsBrowserVerification() {
		let error = RSSHubError.subscriptionFailure(
			forUserEnteredURL: "rsshub://caixin/latest",
			underlying: StubRetrievalFailure(httpStatusCode: 403, requiresBrowserVerification: true)
		)
		#expect(error as? RSSHubError == .browserVerificationRequired(statusCode: 403))
	}

	private func failure(forUserEnteredURL urlString: String, statusCode: Int?, settings: RSSHubSettings? = nil) -> RSSHubError? {
		let resolvedSettings: RSSHubSettings
		if let settings {
			resolvedSettings = settings
		} else {
			let defaults = UserDefaults(suiteName: "rsshub-error-tests-\(UUID().uuidString)")!
			defaults.set("https://rsshub.app", forKey: "rsshub.baseURL")
			resolvedSettings = RSSHubSettings(defaults: defaults)
		}
		let error = RSSHubError.subscriptionFailure(
			forUserEnteredURL: urlString,
			settings: resolvedSettings,
			underlying: StubRetrievalFailure(httpStatusCode: statusCode)
		)
		return error as? RSSHubError
	}

	@Test("maps 401 and 403 to access denied")
	func mapsAuthFailures() {
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 401) == .accessDenied(statusCode: 401))
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 403) == .accessDenied(statusCode: 403))
	}

	@Test("maps 404 to route not found")
	func mapsRouteNotFound() {
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 404) == .routeNotFound(statusCode: 404))
	}

	@Test("maps 429 to rate limited")
	func mapsRateLimited() {
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 429) == .rateLimited(statusCode: 429))
	}

	@Test("maps 5xx to server error")
	func mapsServerErrors() {
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 500) == .serverError(statusCode: 500))
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 503) == .serverError(statusCode: 503))
	}

	@Test("maps timeouts and other statuses to unreachable")
	func mapsUnreachable() {
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: nil) == .unreachable(statusCode: nil))
		#expect(failure(forUserEnteredURL: "rsshub://telegram/channel/foo", statusCode: 400) == .unreachable(statusCode: 400))
	}

	@Test("ignores retrieval errors for URLs outside the instance")
	func ignoresOtherHosts() {
		#expect(failure(forUserEnteredURL: "https://daringfireball.net/feeds/main", statusCode: 403) == nil)
	}

	/// Stand-in for a non-retrieval error (already subscribed, account
	/// errors, …) that call sites handle with their own logic.
	private struct StubBusinessError: Error {}

	@Test("keeps business errors like already-subscribed untouched")
	func keepsBusinessErrors() {
		#expect(RSSHubError.subscriptionFailure(
			forUserEnteredURL: "rsshub://telegram/channel/foo",
			underlying: StubBusinessError()
		) == nil)
	}

	@Test("doesn’t misjudge plain https feeds hosted on the instance as RSSHub errors")
	func plainFeedsOnInstanceAreNotConverted() {
		#expect(failure(forUserEnteredURL: "https://rsshub.app/some/custom/rss.xml", statusCode: 403) == nil)
	}
}
