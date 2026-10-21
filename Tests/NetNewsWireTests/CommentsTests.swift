//
//  CommentsTests.swift
//  NetNewsWireTests
//
//  Tests for the comments providers, the HTML parser they are built on, and
//  the renderer that puts a thread into the article view.
//

import Foundation
import Testing
@testable import NetNewsWire

/// A URL protocol that answers from a table of canned responses, so the
/// provider can be exercised without touching the network.
///
/// The table is shared by the whole test process and the tests run
/// concurrently, so it is guarded by a lock and every test keys its
/// responses by a URL of its own.
final class StubURLProtocol: URLProtocol {

	struct Response {
		var statusCode: Int
		var data: Data
	}

	private static let lock = NSLock()
	nonisolated(unsafe) private static var responses: [String: Response] = [:]

	/// Registers the response for any request whose URL contains `urlSubstring`.
	static func setResponse(_ urlSubstring: String, statusCode: Int = 200, data: Data = Data()) {
		lock.lock()
		defer { lock.unlock() }
		responses[urlSubstring] = Response(statusCode: statusCode, data: data)
	}

	private static func response(for urlString: String) -> Response? {
		lock.lock()
		defer { lock.unlock() }
		return responses.first { urlString.contains($0.key) }?.value
	}

	/// A session that routes every request through `StubURLProtocol`.
	static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: configuration)
	}

	override class func canInit(with request: URLRequest) -> Bool {
		true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		guard let url = request.url else {
			client?.urlProtocol(self, didFailWithError: URLError(.badURL))
			return
		}
		let match = Self.response(for: url.absoluteString)
		let httpResponse = HTTPURLResponse(url: url, statusCode: match?.statusCode ?? 404, httpVersion: "HTTP/1.1", headerFields: nil)!
		client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
		if let data = match?.data {
			client?.urlProtocol(self, didLoad: data)
		}
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {
	}
}

@Suite("Article comments")
struct CommentsTests {

    // MARK: - HTML parser

    @Test("Parser reads attributes, nesting and inner HTML")
    func parserReadsStructure() {
        let html = """
        <div class="comment-list" id="comments">
            <article class="comment" data-id="7">
                <div class="comment-author">Ada</div>
                <p>Hello <em>world</em></p>
            </article>
        </div>
        """
        let roots = HTMLElementParser.parse(html)

        #expect(roots.count == 1)
        let list = roots[0]
        #expect(list.name == "div")
        #expect(list.hasClass("comment-list"))
        #expect(list.attribute("id") == "comments")

        let comment = list.descendants(where: { $0.hasClass("comment") }).first
        #expect(comment != nil)
        #expect(comment?.attribute("data-id") == "7")
        #expect(comment?.textContent.contains("Hello") == true)
        #expect(comment?.innerHTML.contains("<em>world</em>") == true)
    }

    @Test("Parser handles void elements, unclosed tags and raw text")
    func parserHandlesAwkwardHTML() {
        let html = """
        <p>one<br>two</p>
        <div><span>unclosed
        <script>var a = "<div class='fake'>";</script>
        """
        let roots = HTMLElementParser.parse(html)

        let paragraph = roots.first { $0.name == "p" }
        #expect(paragraph != nil)
        #expect(paragraph?.textContent.contains("one") == true)
        #expect(paragraph?.textContent.contains("two") == true)

        // The markup inside the script element must not become real elements.
        #expect(roots.first { $0.hasClass("fake") } == nil)
    }

    @Test("Parser keeps attribute values with spaces and quotes")
    func parserReadsAttributeValues() {
        let html = "<a href=\"/member/some one\" title='He said \"hi\"'>link</a>"
        let roots = HTMLElementParser.parse(html)
        let anchor = roots.first
        #expect(anchor?.attribute("href") == "/member/some one")
        #expect(anchor?.attribute("title") == "He said \"hi\"")
    }

    // MARK: - Sanitizer

    @Test("Sanitizer removes scripts, handlers and javascript URLs")
    func sanitizerStripsDangerousContent() {
        let html = """
        <p onclick="steal()">hi</p><script>alert(1)</script><a href="javascript:alert(2)">x</a>
        """
        let sanitized = CommentHTMLSanitizer.sanitized(html)

        #expect(sanitized.contains("onclick") == false)
        #expect(sanitized.contains("<script") == false)
        #expect(sanitized.contains("javascript:") == false)
        #expect(sanitized.contains("hi") == true)
    }

    // MARK: - V2EX provider

    @Test("V2EX provider recognizes topic URLs")
    func v2exRecognizesTopicURLs() throws {
        let provider = V2EXCommentsProvider()

        let topicURL = try #require(URL(string: "https://www.v2ex.com/t/1249625#reply5"))
        #expect(provider.canProvideComments(for: topicURL))
        #expect(provider.topicID(for: topicURL) == 1249625)

        let otherURL = try #require(URL(string: "https://example.com/t/1249625"))
        #expect(provider.canProvideComments(for: otherURL) == false)
    }

    @Test("V2EX provider reads replies from the JSON API")
    func v2exReadsRepliesFromAPI() async throws {
        let json = """
        [
          {
            "id": 18192581,
            "created": 1792233452,
            "content": "只需要 tun 模式的代理",
            "content_rendered": "<p>只需要 tun 模式的代理</p>",
            "member": {
              "username": "wangwaner",
              "avatar_normal": "https://cdn.v2ex.com/gravatar/abc?s=48",
              "url": "https://www.v2ex.com/u/wangwaner"
            }
          },
          {
            "id": 18192584,
            "created": 1792233519,
            "content": "没买之前要用 cc-switch",
            "content_rendered": "<p>没买之前要用 cc-switch</p>",
            "member": { "username": "kerwin1874" }
          }
        ]
        """
        StubURLProtocol.setResponse("topic_id=1249625", data: Data(json.utf8))

        let provider = V2EXCommentsProvider(session: StubURLProtocol.makeSession())
        let url = try #require(URL(string: "https://www.v2ex.com/t/1249625"))
        let comments = try await provider.fetchComments(for: url)

        #expect(comments.count == 2)
        let first = try #require(comments.first)
        let second = try #require(comments.dropFirst().first)
        #expect(first.authorName == "wangwaner")
        #expect(first.bodyHTML.contains("只需要 tun 模式的代理"))
        #expect(first.authorAvatarURL?.absoluteString == "https://cdn.v2ex.com/gravatar/abc?s=48")
        #expect(second.authorName == "kerwin1874")
        #expect(first.permalink?.absoluteString.contains("#reply18192581") == true)
    }

    @Test("V2EX provider falls back to parsing the topic page")
    func v2exFallsBackToTopicPage() async throws {
        // The JSON endpoint fails…
        StubURLProtocol.setResponse("topic_id=777777", statusCode: 500)

        let pageHTML = """
        <html><body>
        <div id="r_18192581" class="cell">
          <table><tr><td>
            <img src="https://cdn.v2ex.com/gravatar/abc?s=48" class="avatar" alt="wangwaner" />
            <strong><a href="/member/wangwaner" class="dark">wangwaner</a></strong>
            <span class="ago" title="2026-10-17 18:37:32 +08:00">3 days ago via iPhone</span>
            <div class="reply_content">只需要 tun 模式的代理+官方客户端直接登录就好了</div>
          </td></tr></table>
        </div>
        </body></html>
        """
        StubURLProtocol.setResponse("v2ex.com/t/777777", data: Data(pageHTML.utf8))

        let provider = V2EXCommentsProvider(session: StubURLProtocol.makeSession())
        let url = try #require(URL(string: "https://www.v2ex.com/t/777777"))
        let comments = try await provider.fetchComments(for: url)

        #expect(comments.count == 1)
        let comment = try #require(comments.first)
        #expect(comment.authorName == "wangwaner")
        #expect(comment.bodyHTML.contains("只需要 tun 模式的代理"))
        #expect(comment.date != nil)
    }

    @Test("V2EX provider returns nothing when the topic has no replies")
    func v2exHandlesEmptyThread() async throws {
        StubURLProtocol.setResponse("topic_id=999999", data: Data("[]".utf8))

        let provider = V2EXCommentsProvider(session: StubURLProtocol.makeSession())
        let url = try #require(URL(string: "https://www.v2ex.com/t/999999"))
        let comments = try await provider.fetchComments(for: url)

        #expect(comments.isEmpty)
    }

    // MARK: - Service

    @Test("Service only asks providers that claim the URL")
    func serviceSelectsProviderByURL() async throws {
        let provider = V2EXCommentsProvider()
        let service = CommentsService(providers: [provider])

        let topicURL = try #require(URL(string: "https://www.v2ex.com/t/1249625"))
        #expect(service.provider(for: topicURL) != nil)

        let otherURL = try #require(URL(string: "https://example.com/post/1"))
        #expect(service.provider(for: otherURL) == nil)
        // A URL no provider serves must not trigger any network request.
        #expect(await service.comments(for: otherURL).isEmpty)
    }

    // MARK: - Renderer

    @Test("Renderer produces a thread with author, body and count")
    func rendererProducesThread() {
        let comment = ArticleComment(
            id: "v2ex-1",
            authorName: "wangwaner",
            authorAvatarURL: URL(string: "https://cdn.v2ex.com/avatar.png"),
            authorURL: URL(string: "https://www.v2ex.com/u/wangwaner"),
            bodyHTML: "<p>hello</p>",
            date: Date(timeIntervalSince1970: 1792233452),
            permalink: URL(string: "https://www.v2ex.com/t/1#reply1")
        )
        let html = CommentsHTMLRenderer.html(for: [comment], sourceName: "V2EX")

        #expect(html.contains("articleComments"))
        #expect(html.contains("data-comments-source=\"V2EX\""))
        #expect(html.contains("wangwaner"))
        #expect(html.contains("<p>hello</p>"))
        #expect(html.contains("articleCommentAvatar"))
        #expect(html.contains("#reply1"))
    }

    @Test("Renderer escapes the author name")
    func rendererEscapesAuthorName() {
        let comment = ArticleComment(id: "1", authorName: "<script>bad()</script>", bodyHTML: "hi")
        let html = CommentsHTMLRenderer.html(for: [comment], sourceName: "Test")
        #expect(html.contains("<script>") == false)
        #expect(html.contains("&lt;script&gt;") == true)
    }

    @Test("Renderer returns nothing for an empty thread")
    func rendererHandlesEmptyThread() {
        #expect(CommentsHTMLRenderer.html(for: [], sourceName: "V2EX").isEmpty)
    }
}
