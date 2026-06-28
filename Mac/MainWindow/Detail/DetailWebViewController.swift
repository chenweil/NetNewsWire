//
//  DetailWebViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/11/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import Articles
import Images
import ArticlesDatabase
import Account

@MainActor protocol DetailWebViewControllerDelegate: AnyObject {
	func mouseDidEnter(_: DetailWebViewController, link: String)
	func mouseDidExit(_: DetailWebViewController)
}

final class DetailWebViewController: NSViewController {

	weak var delegate: DetailWebViewControllerDelegate?
	var webView: DetailWebView!

	// MARK: - Translation Support

	/// Translation coordinator for translating articles. Injected dependency for testing.
	var translationCoordinator: TranslationCoordinator?

	/// Current translation status. Observable by UI.
	var translationStatus: TranslationStatus = .idle {
		didSet {
			guard isViewLoaded else { return }
			reloadHTMLMaintainingScrollPosition()
		}
	}

	// MARK: - Initialization

	/// Creates a DetailWebViewController with an optional translation coordinator.
	/// - Parameter translationCoordinator: The coordinator to use for translation. Pass nil to disable translation.
	init(translationCoordinator: TranslationCoordinator? = nil) {
		self.translationCoordinator = translationCoordinator
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var state: DetailState = .noSelection {
		didSet {
			if state != oldValue {
				switch state {
				case .article(_, let scrollY), .extracted(_, _, let scrollY):
					windowScrollY = scrollY
				default:
					break
				}
				// Only reload HTML if the view is loaded
				if isViewLoaded {
					reloadHTML()
				}
				// Trigger translation for new articles
				requestTranslationIfNeeded()
			}
		}
	}

	var windowState: DetailWindowState {
		DetailWindowState(isShowingExtractedArticle: isShowingExtractedArticle, windowScrollY: windowScrollY ?? 0)
	}

	var article: Article? {
		switch state {
		case .article(let article, _):
			return article
		case .extracted(let article, _, _):
			return article
		default:
			return nil
		}
	}

	private var articleTextSize = AppDefaults.shared.articleTextSize

	private var webInspectorEnabled: Bool {
		get {
			return webView.configuration.preferences._developerExtrasEnabled
		}
		set {
			webView.configuration.preferences._developerExtrasEnabled = newValue
		}
	}

	private let detailIconSchemeHandler = DetailIconSchemeHandler()
	private var waitingForFirstReload = false
	private var isReloadingHTML = false
	private let keyboardDelegate = DetailKeyboardDelegate()
	private var windowScrollY: CGFloat?

	private var isShowingExtractedArticle: Bool {
		switch state {
		case .extracted:
			return true
		default:
			return false
		}
	}

	private struct MessageName {
		static let mouseDidEnter = "mouseDidEnter"
		static let mouseDidExit = "mouseDidExit"
		static let windowDidScroll = "windowDidScroll"
	}

	override func loadView() {

		let configuration = WebViewConfiguration.configuration(with: detailIconSchemeHandler)

		configuration.userContentController.add(self, name: MessageName.windowDidScroll)
		configuration.userContentController.add(self, name: MessageName.mouseDidEnter)
		configuration.userContentController.add(self, name: MessageName.mouseDidExit)

		webView = DetailWebView(frame: NSRect.zero, configuration: configuration)
		webView.uiDelegate = self
		webView.navigationDelegate = self
		webView.keyboardDelegate = keyboardDelegate
		webView.translatesAutoresizingMaskIntoConstraints = false
		if let userAgent = UserAgent.fromInfoPlist() {
			webView.customUserAgent = userAgent
		}

		view = webView

		// Hide the web view until the first reload (navigation) is committed (plus some delay) to avoid the white flash that happens on initial display in dark mode.
		// See bug #901.
		webView.isHidden = true
		waitingForFirstReload = true

		webInspectorEnabled = AppDefaults.shared.webInspectorEnabled
		NotificationCenter.default.addObserver(self, selector: #selector(webInspectorEnabledDidChange(_:)), name: .WebInspectorEnabledDidChange, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)

		webView.loadFileURL(ArticleRenderer.blank.url, allowingReadAccessTo: ArticleRenderer.blank.baseURL)
	}

	// MARK: Notifications

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	func userDefaultsDidChange() {
		if articleTextSize != AppDefaults.shared.articleTextSize {
			articleTextSize = AppDefaults.shared.articleTextSize
			reloadHTMLMaintainingScrollPosition()
		}
	}

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		reloadHTMLMaintainingScrollPosition()
	}

	// MARK: Media Functions

	func stopMediaPlayback() {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}

	func translateCurrentArticle() {
		guard let article = article,
			  let account = AccountManager.shared.existingAccount(accountID: article.accountID) else {
			return
		}

		translationCoordinator = TranslationCoordinator.live(articlesDatabase: account.articlesDatabase)

		if case .failed = translationStatus {
			retryTranslation()
		} else {
			requestTranslationIfNeeded()
		}
	}

	// MARK: Scrolling

	func canScrollDown() async -> Bool {
		let scrollInfo = await fetchScrollInfo()
		return scrollInfo?.canScrollDown ?? false
	}

	func canScrollUp() async -> Bool {
		let scrollInfo = await fetchScrollInfo()
		return scrollInfo?.canScrollUp ?? false
	}

	override func scrollPageDown(_ sender: Any?) {
		webView.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		webView.scrollPageUp(sender)
	}
}

// MARK: - WKScriptMessageHandler

extension DetailWebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == MessageName.windowDidScroll {
			windowScrollY = message.body as? CGFloat
		} else if message.name == MessageName.mouseDidEnter, let link = message.body as? String {
			delegate?.mouseDidEnter(self, link: link)
		} else if message.name == MessageName.mouseDidExit {
			delegate?.mouseDidExit(self)
		}
	}
}

// MARK: - WKNavigationDelegate & WKUIDelegate

extension DetailWebViewController: WKNavigationDelegate, WKUIDelegate {

	// Bottleneck through which WebView-based URL opens go
	func openInBrowser(_ url: URL, flags: NSEvent.ModifierFlags) {
		let invert = flags.contains(.shift) || flags.contains(.command)
		Browser.open(url.absoluteString, invertPreference: invert)
	}

	// WKNavigationDelegate

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
		if navigationAction.navigationType == .linkActivated {
			if let url = navigationAction.request.url {
				self.openInBrowser(url, flags: navigationAction.modifierFlags)
			}
			decisionHandler(.cancel)
			return
		}

		decisionHandler(.allow)
	}

	public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		// See note in loadView()
		guard waitingForFirstReload else {
			return
		}

		assert(webView.isHidden)
		waitingForFirstReload = false
		reloadHTML()

		// Waiting for the first navigation to commit isn't enough to avoid the flash of white.
		// Delaying an additional half a second seems to be enough.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			webView.isHidden = false
		}
	}

	public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard let windowScrollY else {
			return
		}
		webView.evaluateJavaScript("window.scrollTo(0, \(windowScrollY));")
		self.windowScrollY = nil
	}

	// WKUIDelegate

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// This method is reached when WebKit handles a JavaScript based window.open() invocation, for example. One
		// example where this is used is in YouTube's embedded video player when a user clicks on the video's title
		// or on the "Watch in YouTube" button. For our purposes we'll handle such window.open calls the same way we
		// handle clicks on a URL.
		if let url = navigationAction.request.url {
			self.openInBrowser(url, flags: navigationAction.modifierFlags)
		}

		return nil
	}
}

// MARK: - Private

private extension DetailWebViewController {

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func reloadHTMLMaintainingScrollPosition() {
		fetchScrollInfo { scrollInfo in
			self.windowScrollY = scrollInfo?.offsetY
			self.reloadHTML()
		}
	}

	func reloadHTML() {
		// Guard against a re-entrancy crash.
		if isReloadingHTML {
			return
		}
		isReloadingHTML = true
		defer {
			isReloadingHTML = false
		}

		delegate?.mouseDidExit(self)

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		switch state {
		case .noSelection:
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		case .multipleSelection:
			rendering = ArticleRenderer.multipleSelectionHTML(theme: theme)
		case .loading:
			rendering = ArticleRenderer.loadingHTML(theme: theme)
		case .article(let article, _):
			detailIconSchemeHandler.currentArticle = article
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		case .extracted(let article, let extractedArticle, _):
			detailIconSchemeHandler.currentArticle = article
			rendering = ArticleRenderer.articleHTML(article: article, extractedArticle: extractedArticle, theme: theme)
		}

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": htmlForCurrentTranslationStatus(rendering.html)
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)
		WebViewConfiguration.addContentBlockingRules(to: webView)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	func htmlForCurrentTranslationStatus(_ articleHTML: String) -> String {
		switch translationStatus {
		case .idle:
			return articleHTML
		case .translating:
			return """
			<div class="translationStatus">\(NSLocalizedString("Translating...", comment: "Translation status"))</div>
			\(articleHTML)
			"""
		case .translated(let translation):
			let titleHTML: String
			if translation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				titleHTML = ""
			} else {
				titleHTML = """
				<div class="articleTitle"><h1>\(translation.title.escapedHTML)</h1></div>
				"""
			}
			return """
			<div class="translationStatus">\(NSLocalizedString("Translated", comment: "Translation status"))</div>
			<article>
			\(titleHTML)
			<div class="translatedArticleBody articleBody" data-translation-typewriter>\(translation.body)</div>
			\(translationTypewriterScript)
			</article>
			"""
		case .failed(let message):
			return """
			<div class="translationStatus">\(NSLocalizedString("Translation Failed", comment: "Translation status")): \(message.escapedHTML)</div>
			\(articleHTML)
			"""
		}
	}

	var translationTypewriterScript: String {
		"""
		<script>
		(function() {
			const script = document.currentScript;
			const root = script ? script.previousElementSibling : null;
			if (!root || root.dataset.translationTypewriterStarted === "true") {
				return;
			}
			if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
				root.dataset.translationTypewriterComplete = "true";
				return;
			}

			root.dataset.translationTypewriterStarted = "true";
			const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
			const textNodes = [];
			let node;
			while ((node = walker.nextNode())) {
				if (!node.nodeValue || node.nodeValue.trim().length === 0) {
					continue;
				}
				textNodes.push({ node: node, text: node.nodeValue });
				node.nodeValue = "";
			}

			if (textNodes.length === 0) {
				root.dataset.translationTypewriterComplete = "true";
				return;
			}

			const cursor = document.createElement("span");
			cursor.className = "translationTypewriterCursor";
			cursor.textContent = "|";

			let nodeIndex = 0;
			let characterIndex = 0;
			const charactersPerTick = 3;
			const tickDelay = 14;

			function finish() {
				cursor.remove();
				root.dataset.translationTypewriterComplete = "true";
			}

			function moveCursorAfter(node) {
				const parent = node.parentNode;
				if (!parent) {
					return;
				}
				if (cursor.parentNode === parent && cursor.previousSibling === node) {
					return;
				}
				parent.insertBefore(cursor, node.nextSibling);
			}

			function tick() {
				let remaining = charactersPerTick;
				while (remaining > 0 && nodeIndex < textNodes.length) {
					const item = textNodes[nodeIndex];
					moveCursorAfter(item.node);
					const nextIndex = Math.min(characterIndex + remaining, item.text.length);
					item.node.nodeValue += item.text.slice(characterIndex, nextIndex);
					remaining -= nextIndex - characterIndex;
					characterIndex = nextIndex;
					if (characterIndex >= item.text.length) {
						nodeIndex += 1;
						characterIndex = 0;
					}
				}

				if (nodeIndex >= textNodes.length) {
					finish();
				} else {
					window.setTimeout(tick, tickDelay);
				}
			}

			tick();
		})();
		</script>
		"""
	}

	func fetchScrollInfo() async -> ScrollInfo? {
		await withCheckedContinuation { continuation in
			self.fetchScrollInfo { scrollInfo in
				continuation.resume(returning: scrollInfo)
			}
		}
	}

	private func fetchScrollInfo(_ completion: @escaping (ScrollInfo?) -> Void) {
		let javascriptString = "var x = {contentHeight: document.body.scrollHeight, offsetY: document.body.scrollTop}; x"

		webView.evaluateJavaScript(javascriptString) { (info, _) in
			guard let info = info as? [String: Any] else {
				completion(nil)
				return
			}
			guard let contentHeight = info["contentHeight"] as? CGFloat, let offsetY = info["offsetY"] as? CGFloat else {
				completion(nil)
				return
			}

			let scrollInfo = ScrollInfo(contentHeight: contentHeight, viewHeight: self.webView.frame.height, offsetY: offsetY)
			completion(scrollInfo)
		}
	}

	@objc func webInspectorEnabledDidChange(_ notification: Notification) {
		self.webInspectorEnabled = notification.object! as! Bool
	}

		// MARK: - Translation

		/// Requests translation for the current article if needed.
		/// Note: Translation can proceed even if the view isn't loaded yet,
		/// as it only needs the article data, not the web view.
		func requestTranslationIfNeeded() {
			guard let coordinator = translationCoordinator else {
				return
			}

			guard let article = article else {
				translationStatus = .idle
				return
			}

			// Determine body source and content
			let bodySource: ArticleTranslation.BodySource
			let bodyHTML: String

			if case .extracted(_, let extractedArticle, _) = state {
				bodySource = .extractedBody
				bodyHTML = extractedArticle.content ?? ""
			} else {
				bodySource = .feedBody
				bodyHTML = article.body ?? ""
			}

			// Request translation asynchronously
			Task {
				translationStatus = .translating

				let result = await coordinator.translation(
					for: article.articleID,
					title: article.title ?? "",
					bodyHTML: bodyHTML,
					bodySource: bodySource
				)

				switch result {
				case .translated(let translation):
					translationStatus = .translated(translation)
				case .failed(let error):
					translationStatus = .failed(error.localizedDescription)
				case .skipped:
					translationStatus = .idle
				}
			}
		}

		/// Retries translation after a failure.
		func retryTranslation() {
			guard let coordinator = translationCoordinator else {
				return
			}

			guard let article = article else {
				return
			}

			// Determine body source and content
			let bodySource: ArticleTranslation.BodySource
			let bodyHTML: String

			if case .extracted(_, let extractedArticle, _) = state {
				bodySource = .extractedBody
				bodyHTML = extractedArticle.content ?? ""
			} else {
				bodySource = .feedBody
				bodyHTML = article.body ?? ""
			}

			// Retry translation asynchronously
			Task {
				translationStatus = .translating

				let result = await coordinator.retry(
					for: article.articleID,
					title: article.title ?? "",
					bodyHTML: bodyHTML,
					bodySource: bodySource
				)

				switch result {
				case .translated(let translation):
					translationStatus = .translated(translation)
				case .failed(let error):
					translationStatus = .failed(error.localizedDescription)
				case .skipped:
					translationStatus = .idle
				}
			}
		}
}

// MARK: - ScrollInfo

private struct ScrollInfo {

	let contentHeight: CGFloat
	let viewHeight: CGFloat
	let offsetY: CGFloat
	let canScrollDown: Bool
	let canScrollUp: Bool

	init(contentHeight: CGFloat, viewHeight: CGFloat, offsetY: CGFloat) {
		self.contentHeight = contentHeight
		self.viewHeight = viewHeight
		self.offsetY = offsetY

		self.canScrollDown = viewHeight + offsetY < contentHeight
		self.canScrollUp = offsetY > 0.1
	}
}
