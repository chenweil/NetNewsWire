//
//  FeedURLResolverTests.swift
//  RSCoreTests
//

import Foundation
import Testing
@testable import RSCore

private struct StubResolver: FeedURLResolving {

	let handledSchemes: Set<String>
	let resolved: String

	func resolveFeedURL(_ url: URL) throws -> URL {
		guard let url = URL(string: resolved) else {
			throw URLError(.badURL)
		}
		return url
	}
}

private struct Boom: Error {}

private struct FailingResolver: FeedURLResolving {
	let handledSchemes: Set<String> = ["rsshub"]

	func resolveFeedURL(_ url: URL) throws -> URL {
		throw Boom()
	}
}

/// `FeedURLResolver` is process-global, so every test that installs a resolver
/// has to run one at a time.
@Suite(.serialized) struct FeedURLResolverTests {

	private func withStubResolver(_ body: () -> Void) {
		FeedURLResolver.install(StubResolver(handledSchemes: ["rsshub"], resolved: "https://rsshub.app/telegram/channel/foo"))
		defer { FeedURLResolver.install(nil) }
		body()
	}

	@Test("claims is false when nothing is installed")
	func claimsWithoutResolver() {
		FeedURLResolver.install(nil)
		#expect(FeedURLResolver.claims(string: "rsshub://telegram/channel/foo") == false)
	}

	@Test("claims matches the installed resolver’s schemes, case-insensitively")
	func claimsWithResolver() {
		withStubResolver {
			#expect(FeedURLResolver.claims(string: "rsshub://telegram/channel/foo"))
			#expect(FeedURLResolver.claims(string: "RSSHUB://telegram/channel/foo"))
			#expect(FeedURLResolver.claims(string: "https://daringfireball.net/") == false)
		}
	}

	@Test("resolve expands claimed schemes and leaves everything else alone")
	func resolveExpandsClaimedSchemes() throws {
		FeedURLResolver.install(StubResolver(handledSchemes: ["rsshub"], resolved: "https://rsshub.app/telegram/channel/foo"))
		defer { FeedURLResolver.install(nil) }

		let expanded = try FeedURLResolver.resolve("rsshub://telegram/channel/foo")
		let https = try FeedURLResolver.resolve("https://daringfireball.net/feed")
		let schemeless = try FeedURLResolver.resolve("daringfireball.net/feed")
		#expect(expanded == "https://rsshub.app/telegram/channel/foo")
		#expect(https == "https://daringfireball.net/feed")
		#expect(schemeless == "daringfireball.net/feed")
	}

	@Test("resolve propagates resolver failures")
	func resolvePropagatesFailure() {
		FeedURLResolver.install(FailingResolver())
		#expect(throws: Boom.self) {
			try FeedURLResolver.resolve("rsshub://telegram/channel/foo")
		}
		FeedURLResolver.install(nil)
	}

	@Test("mayBeURL accepts an app-specific scheme with no dot in it")
	func mayBeURLAcceptsAppScheme() {
		withStubResolver {
			#expect("rsshub://telegram/channel/zaihuanews".mayBeURL)
			#expect("rsshub://a/b".mayBeURL)
		}
	}

	@Test("mayBeURL still rejects empty and whitespace-bearing input")
	func mayBeURLStillRejectsBadInput() {
		withStubResolver {
			#expect("".mayBeURL == false)
			#expect("   ".mayBeURL == false)
			#expect("rsshub://telegram/channel/foo bar".mayBeURL == false)
		}
	}

	@Test("mayBeURL rejects an app-specific scheme when no resolver is installed")
	func mayBeURLRejectsUnclaimedScheme() {
		FeedURLResolver.install(nil)
		#expect("rsshub://telegram/channel/zaihuanews".mayBeURL == false)
	}

	@Test("mayBeURL behavior for ordinary URLs is unchanged")
	func mayBeURLUnchangedForHTTP() {
		withStubResolver {
			#expect("daringfireball.net".mayBeURL)
			#expect("https://daringfireball.net/".mayBeURL)
			#expect("nonsense".mayBeURL == false)
		}
	}

	@Test("normalizedURL leaves an app-specific scheme untouched instead of corrupting it")
	func normalizedURLLeavesAppSchemeAlone() {
		withStubResolver {
			// The old code turned this into http://rsshub://telegram/channel/zaihuanews.
			#expect("rsshub://telegram/channel/zaihuanews".normalizedURL == "rsshub://telegram/channel/zaihuanews")
			#expect("  rsshub://telegram/channel/zaihuanews  ".normalizedURL == "rsshub://telegram/channel/zaihuanews")
		}
	}

	@Test("normalizedURL still rewrites feed: and feeds:")
	func normalizedURLStillRewritesFeedSchemes() {
		withStubResolver {
			#expect("feed:daringfireball.net".normalizedURL == "http://daringfireball.net/")
			#expect("feeds:daringfireball.net".normalizedURL == "https://daringfireball.net/")
		}
	}
}