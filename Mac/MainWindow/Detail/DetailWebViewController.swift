//
//  DetailWebViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/11/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit
@preconcurrency import WebKit
import os
import RSCore
import Articles
import Images
import ArticlesDatabase
import Account

@MainActor protocol DetailWebViewControllerDelegate: AnyObject {
	func mouseDidEnter(_: DetailWebViewController, link: String)
	func mouseDidExit(_: DetailWebViewController)
}

final class DetailWebViewController: NSViewController {

	static private let logger = Logger(subsystem: Logger.nnwSubsystem, category: "DetailWebViewController")

	weak var delegate: DetailWebViewControllerDelegate?
	var webView: DetailWebView!

	// MARK: - Translation Support

	/// Translation coordinator for translating articles. Injected dependency for testing.
	var translationCoordinator: TranslationCoordinator?

	/// Current translation status. Observable by UI.
	var translationStatus: TranslationStatus = .idle {
		didSet {
			if case .translating = translationStatus {
				streamedTranslationBody = ""
			}
			notifyTranslationAvailabilityChanged()
			guard isViewLoaded else { return }
			// The reset between articles is rendered by the article change
			// itself, so it must not trigger a second render.
			guard !isResettingTranslationStatus else { return }
			// Re-render only when the status actually changed: the article
			// view is re-rendered on every article change already.
			guard translationStatus != oldValue else { return }
			reloadHTMLMaintainingScrollPosition()
		}
	}

	/// Called whenever the article view gains or loses a translation, so the
	/// display-mode control can be enabled or disabled to match.
	var onTranslationAvailabilityChanged: ((Bool) -> Void)?

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

	deinit {
		translationTask?.cancel()
		skipCheckTask?.cancel()
		commentsTask?.cancel()
	}

	var state: DetailState = .noSelection {
		didSet {
			if state != oldValue {
				commentsTask?.cancel()
				commentsHTML = ""
				// Drop the previous article's translation before the new
				// article is rendered, so it never shows up under the new
				// article's body.
				isResettingTranslationStatus = true
				translationStatus = .idle
				isResettingTranslationStatus = false
				switch state {
				case .article(_, let scrollY), .extracted(_, _, let scrollY):
					windowScrollY = scrollY
					pendingScrollRestorationY = scrollY
				default:
					break
				}
				// Only reload HTML if the view is loaded
				if isViewLoaded {
					reloadHTML()
				}
				// Trigger translation for new articles
				requestTranslationIfNeeded()
				requestCommentsIfNeeded()
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

	private var articleTextSize = AppDefaults.articleTextSize
	private var isArticleContentJavascriptEnabled = AppDefaults.isArticleContentJavascriptEnabled

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
	private var translationTask: Task<Void, Never>?
	private var skipCheckTask: Task<Void, Never>?
	private var streamedTranslationBody = ""
	private var commentsTask: Task<Void, Never>?
	private var commentsHTML = ""

	/// Set while the translation status is being reset between articles, so
	/// the reset does not trigger a render of its own.
	private var isResettingTranslationStatus = false

	/// Counts the reloads that have been requested, so that only the most
	/// recent one renders.
	private var reloadToken = 0

	// The scroll offset to apply to the next-loaded article. Kept separate from windowScrollY,
	// which windowDidScroll messages still arriving from the previous article can overwrite.
	private var pendingScrollRestorationY: CGFloat?

	// The page posts windowDidScroll continuously while scrolling, including during momentum.
	private var lastWindowDidScrollMessageDate: Date?
	private static let recentScrollInterval: TimeInterval = 0.2

	private var webViewMayStillBeScrolling: Bool {
		guard let lastWindowDidScrollMessageDate else {
			return false
		}
		return Date().timeIntervalSince(lastWindowDidScrollMessageDate) < Self.recentScrollInterval
	}

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

		view = NSView()

		webView = createWebView()
		view.addSubview(webView)

		// Hide the web view until the first reload (navigation) is committed (plus some delay) to avoid the white flash that happens on initial display in dark mode.
		// See bug #901.
		webView.isHidden = true
		waitingForFirstReload = true

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
		if articleTextSize != AppDefaults.articleTextSize {
			articleTextSize = AppDefaults.articleTextSize
			reloadHTMLMaintainingScrollPosition()
		}
		if isArticleContentJavascriptEnabled != AppDefaults.isArticleContentJavascriptEnabled {
			isArticleContentJavascriptEnabled = AppDefaults.isArticleContentJavascriptEnabled
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

		switch translationStatus {
		case .failed, .streamingFailed:
			retryTranslation()
		default:
			requestTranslationIfNeeded()
		}
	}

	/// Switches how a translated article's body is displayed (issue #9). The
	/// mode is persisted and applied to the article view.
	///
	/// The rendered HTML always carries the current mode, so re-rendering
	/// always produces the right result. When the page is already showing a
	/// translation, the page is updated in place instead: that is instant and
	/// it does not replay the typewriter reveal. When the page cannot update
	/// itself — article JavaScript is off, or the page has not finished
	/// loading — the article is re-rendered instead.
	func setTranslationDisplayMode(_ mode: TranslationDisplayMode) {
		TranslationSettings.shared.displayMode = mode
		guard isViewLoaded else {
			return
		}
		webView.evaluateJavaScript("window.setTranslationDisplayMode('\(mode.rawValue)');") { [weak self] result, _ in
			guard (result as? Bool) != true else {
				return
			}
			Task { @MainActor in
				self?.reloadHTMLMaintainingScrollPosition()
			}
		}
	}

	/// Whether the article view currently has a translation the display-mode
	/// control can act on.
	var hasTranslation: Bool {
		if case .translated = translationStatus {
			return true
		}
		return false
	}

	// MARK: Selection

	func fetchSelectedHTML(_ completion: @escaping (String?) -> Void) {
		webView.evaluateJavaScript("selectedHTML()") { result, _ in
			guard let selectedHTML = (result as? String)?.trimmingWhitespace, !selectedHTML.isEmpty else {
				completion(nil)
				return
			}
			completion(selectedHTML)
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
			lastWindowDidScrollMessageDate = Date()
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

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
		if navigationAction.navigationType == .linkActivated {
			if let url = navigationAction.request.url {
				self.openInBrowser(url, flags: navigationAction.modifierFlags)
			}
			decisionHandler(.cancel, preferences)
			return
		}

		// <https://github.com/Ranchero-Software/NetNewsWire/issues/5381>
		if navigationAction.navigationType == .backForward {
			decisionHandler(.cancel, preferences)
			return
		}

		preferences.allowsContentJavaScript = WebViewConfiguration.allowsContentJavaScript(for: article)
		decisionHandler(.allow, preferences)
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
		guard webView === self.webView else {
			return
		}

		removeOldWebViews()

		if let pendingScrollRestorationY {
			webView.evaluateJavaScript("window.scrollTo(0, \(pendingScrollRestorationY));")
			self.pendingScrollRestorationY = nil
		}
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		// Content process died — swap in a fresh web view and re-render.
		guard webView === self.webView else {
			return
		}
		Self.logger.error("Article web content process terminated — rebuilding the web view.")
		let newWebView = createWebView()
		view.addSubview(newWebView, positioned: .below, relativeTo: self.webView)
		self.webView = newWebView
		reloadHTML()
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

	/// The body HTML and source the article view is currently displaying:
	/// the extracted body when Reader View is on, the feed body otherwise.
	var currentBodyInfo: (html: String, source: ArticleTranslation.BodySource) {
		if case .extracted(_, let extractedArticle, _) = state {
			return (extractedArticle.content ?? "", .extractedBody)
		}
		return (article?.body ?? "", .feedBody)
	}

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func createWebView() -> DetailWebView {
		let configuration = WebViewConfiguration.configuration(with: detailIconSchemeHandler)

		configuration.userContentController.add(self, name: MessageName.windowDidScroll)
		configuration.userContentController.add(self, name: MessageName.mouseDidEnter)
		configuration.userContentController.add(self, name: MessageName.mouseDidExit)

		let webView = DetailWebView(frame: view.bounds, configuration: configuration)
		webView.uiDelegate = self
		webView.navigationDelegate = self
		webView.keyboardDelegate = keyboardDelegate
		webView.autoresizingMask = [.width, .height]
		webView.configuration.preferences._developerExtrasEnabled = AppDefaults.webInspectorEnabled

		return webView
	}

	// Old web views stay on top until the new one finishes loading — see reloadHTML().
	func removeOldWebViews() {
		for subview in view.subviews {
			guard let oldWebView = subview as? DetailWebView, oldWebView !== webView else {
				continue
			}
			if let window = view.window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: oldWebView) {
				window.makeFirstResponder(webView)
			}
			oldWebView.removeFromSuperview()
		}
	}

	func reloadHTMLMaintainingScrollPosition() {
		// Several reloads can be in flight at once — the scroll position is
		// fetched asynchronously. Only the most recent one may render, or an
		// older request can land last and show stale content.
		reloadToken += 1
		let token = reloadToken
		fetchScrollInfo { scrollInfo in
			guard token == self.reloadToken else {
				return
			}
			self.pendingScrollRestorationY = scrollInfo?.offsetY
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
		// When the old article may still be scrolling, swap in a fresh web view for the
		// new content. Scrolling momentum lives in the web content process and survives
		// loading new HTML — replacing the web view is what keeps a flick on the old
		// article from scrolling the new one.
		// The old web view stays on top until the new one finishes loading, which also
		// covers the new web view's first paint.
		// <https://github.com/Ranchero-Software/NetNewsWire/issues/901>
		if !webView.isHidden && webViewMayStillBeScrolling {
			Self.logger.debug("DetailWebViewController: swapping in a fresh web view because the old one may still be scrolling")
			let newWebView = createWebView()
			view.addSubview(newWebView, positioned: .below, relativeTo: webView)
			webView = newWebView
		}

		WebViewConfiguration.addContentBlockingRules(to: webView)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	func htmlForCurrentTranslationStatus(_ articleHTML: String) -> String {
		switch translationStatus {
		case .idle:
			return articleHTML + commentsHTML
		case .translating:
			return """
			<div class="translationStatus"><span>\(NSLocalizedString("Translating", comment: "Translation status"))</span><span data-translation-loading-dots>...</span></div>
			\(translationSkeletonHTML)
			\(translationLoadingScript)
			\(articleHTML)\(commentsHTML)
			"""
		case .translated(let translation):
			let displayMode = TranslationSettings.shared.displayMode
			let showOriginal = displayMode == .bilingual || displayMode == .original
			let showTranslated = displayMode == .bilingual || displayMode == .translation
			let originalHidden = showOriginal ? "" : " hidden"
			let translatedHidden = showTranslated ? "" : " hidden"
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
			<article data-translation-display>
			\(titleHTML)
			<div class="articleBody" data-translation-mode-content="original"\(originalHidden)>\(currentBodyInfo.html)</div>
			<hr class="translationSeparator" data-translation-separator\(showOriginal && showTranslated ? "" : " hidden")>
			<div class="translatedArticleBody articleBody" data-translation-mode-content="translation" data-translation-typewriter\(translatedHidden)>\(translation.body)</div>
			\(translationTypewriterScript)
			\(translationDisplayModeScript)
			</article>
			\(commentsHTML)
			"""
		case .failed(let message):
			return """
			<div class="translationStatus">\(NSLocalizedString("Translation Failed", comment: "Translation status")): \(message.escapedHTML)</div>
			\(articleHTML)\(commentsHTML)
			"""
		case .skipped(let reason):
			let message: String
			switch reason {
			case .disabled:
				message = NSLocalizedString("Translation is off. Turn it on in Preferences → Translation.", comment: "Translation status")
			case .sourceMatchesTarget:
				message = NSLocalizedString("This article is already in your target language — nothing to translate.", comment: "Translation status")
			}
			return """
			<div class="translationStatus">\(message)</div>
			\(articleHTML)\(commentsHTML)
			"""
		case .streamingFailed(let message, let partialBody):
			return """
			<div class="translationStatus">\(NSLocalizedString("Translation Failed", comment: "Translation status")): \(message.escapedHTML)</div>
			\(translationPartialHTML(body: partialBody))
			\(articleHTML)\(commentsHTML)
			"""
		}
	}

	/// Placeholder shown while the translation is being produced.
	///
	/// The translation engine returns HTML, and a partial translation is not
	/// valid HTML yet — showing it as it arrives dumped raw markup into the
	/// article view. Instead the reader sees a shimmering skeleton standing in
	/// for the incoming text, and the finished translation fades in over it.
	///
	/// The lines are spans, not divs: the shared stylesheet resets the height
	/// of every div, which would collapse them to nothing.
	var translationSkeletonHTML: String {
		"""
		<div class="translationSkeleton" data-translation-skeleton aria-hidden="true">
		<span class="translationSkeletonLine"></span>
		<span class="translationSkeletonLine"></span>
		<span class="translationSkeletonLine"></span>
		<span class="translationSkeletonLine"></span>
		<span class="translationSkeletonLine"></span>
		<span class="translationSkeletonLine"></span>
		</div>
		"""
	}

	/// Renders the partial translation left behind by a failed stream.
	///
	/// The partial body is HTML from the translation engine. Showing it as-is
	/// would put markup into the article view, so the tags are stripped and
	/// only the text is shown.
	func translationPartialHTML(body: String) -> String {
		let text = AppleTranslationEngine.stripHTML(body)
		guard !text.isEmpty else { return "" }
		return """
		<div class="translationPartial" data-translation-partial>\(text.escapedHTML)</div>
		"""
	}

	var translationLoadingScript: String {
		"""
		<script>
		(function() {
			const dots = document.querySelector("[data-translation-loading-dots]");
			if (!dots || dots.dataset.translationLoadingStarted === "true") {
				return;
			}
			if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
				return;
			}

			dots.dataset.translationLoadingStarted = "true";
			let count = 3;
			setInterval(function() {
				count = (count + 1) % 4;
				dots.textContent = ".".repeat(count);
			}, 500);
		})();
		</script>
		"""
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

	/// JS bridge for the display mode toggle (issue #9). All three content
	/// blocks are rendered once; switching only toggles visibility, so no
	/// re-fetch or re-render is needed.
	var translationDisplayModeScript: String {
		"""
		<script>
		(function() {
			function root() {
				return document.querySelector("[data-translation-display]");
			}

			window.setTranslationDisplayMode = function(mode) {
				const container = root();
				if (!container) {
					return false;
				}
				const showOriginal = (mode === "bilingual" || mode === "original");
				const showTranslated = (mode === "bilingual" || mode === "translation");
				container.querySelectorAll("[data-translation-mode-content]").forEach(function(element) {
					const isOriginal = (element.dataset.translationModeContent === "original");
					element.hidden = isOriginal ? !showOriginal : !showTranslated;
				});
				const separator = container.querySelector("[data-translation-separator]");
				if (separator) {
					separator.hidden = !(showOriginal && showTranslated);
				}
				return true;
			};

			window.setTranslationDisplayMode("\(TranslationSettings.shared.displayMode.rawValue)");
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

	func cancelTranslationTask() {
		translationTask?.cancel()
		translationTask = nil
	}

	/// Accumulates the streamed translation.
	///
	/// The stream is not shown while it arrives: a partial translation is
	/// incomplete HTML, and showing it verbatim dumped raw markup into the
	/// article view. The reader sees a placeholder instead, and the finished
	/// translation when it is ready. The accumulated body is still kept, so a
	/// stream that fails halfway can show the text it did produce.
	func receiveTranslationDelta(_ delta: String) {
		guard !delta.isEmpty else { return }
		streamedTranslationBody.append(delta)
	}

		// MARK: - Translation

		/// Requests translation for the current article if needed.
		/// Note: Translation can proceed even if the view isn't loaded yet,
		/// as it only needs the article data, not the web view.
		func requestTranslationIfNeeded() {
			cancelTranslationTask()
			skipCheckTask?.cancel()

			guard let article = article else {
				translationStatus = .idle
				return
			}

			// Determine body source and content.
			let (bodyHTML, bodySource) = currentBodyInfo
			let title = article.title ?? ""

			guard let coordinator = translationCoordinator else {
				// The reader has not asked for a translation yet. Work out
				// locally whether a translation would be skipped, so the
				// display-mode control is not left looking broken.
				updateLocalSkipStatus(for: title, bodyHTML: bodyHTML)
				return
			}

			translationStatus = .translating
			let articleID = article.articleID
			translationTask = Task { [weak self] in
				let result = await coordinator.streamingTranslation(
					for: articleID,
					title: title,
					bodyHTML: bodyHTML,
					bodySource: bodySource,
					onBodyDelta: { @MainActor [weak self] delta in
						self?.receiveTranslationDelta(delta)
					}
				)

				guard let self, !Task.isCancelled, self.article?.articleID == articleID else {
					return
				}

				switch result {
				case .translated(let translation):
					self.translationStatus = .translated(translation)
				case .failed(let error):
					if self.streamedTranslationBody.isEmpty {
						self.translationStatus = .failed(error.localizedDescription)
					} else {
						self.translationStatus = .streamingFailed(
							error.localizedDescription,
							partialBody: self.streamedTranslationBody
						)
					}
				case .skipped(let reason):
					self.translationStatus = .skipped(reason)
				}
			}
		}

		/// Works out, locally, whether a translation would be skipped for this
		/// article and reports it.
		///
		/// This mirrors the skip rule the coordinator applies when it does
		/// translate, but it runs before any coordinator exists — the reader
		/// has not asked for a translation yet — and it does no cache lookup,
		/// no network request and no engine call.
		///
		/// The language detection loads a language model, so it runs off the
		/// main thread. The result only replaces an `.idle` status: a
		/// translation that started in the meantime wins.
		func updateLocalSkipStatus(for title: String, bodyHTML: String) {
			translationStatus = .idle
			skipCheckTask = Task { [weak self] in
				let status = await Task.detached(priority: .userInitiated) { () -> TranslationStatus? in
					guard TranslationSettings.shared.isEnabled else {
						return .skipped(.disabled)
					}
					guard TranslationSettings.shared.skipWhenSourceMatchesTarget else {
						return nil
					}
					let matches = SourceLanguageInspector.live().sourceMatchesTarget(
						title: title,
						bodyHTML: bodyHTML,
						targetLanguage: TranslationSettings.shared.targetLanguage
					)
					return matches ? .skipped(.sourceMatchesTarget) : nil
				}.value
				guard let self, !Task.isCancelled, let status else { return }
				guard self.translationStatus == .idle else { return }
				self.translationStatus = status
			}
		}

		/// Retries translation after a failure.
		func retryTranslation() {
			cancelTranslationTask()

			guard let coordinator = translationCoordinator else {
				return
			}

			guard let article = article else {
				return
			}

			// Determine body source and content.
			let (bodyHTML, bodySource) = currentBodyInfo

			translationStatus = .translating
			let articleID = article.articleID
			let title = article.title ?? ""
			translationTask = Task { [weak self] in
				let result = await coordinator.streamingRetry(
					for: articleID,
					title: title,
					bodyHTML: bodyHTML,
					bodySource: bodySource,
					onBodyDelta: { @MainActor [weak self] delta in
						self?.receiveTranslationDelta(delta)
					}
				)

				guard let self, !Task.isCancelled, self.article?.articleID == articleID else {
					return
				}

				switch result {
				case .translated(let translation):
					self.translationStatus = .translated(translation)
				case .failed(let error):
					if self.streamedTranslationBody.isEmpty {
						self.translationStatus = .failed(error.localizedDescription)
					} else {
						self.translationStatus = .streamingFailed(
							error.localizedDescription,
							partialBody: self.streamedTranslationBody
						)
					}
				case .skipped(let reason):
					self.translationStatus = .skipped(reason)
				}
			}
		}

		/// Tells the rest of the UI whether the display-mode control has
		/// something to act on.
		func notifyTranslationAvailabilityChanged() {
			onTranslationAvailabilityChanged?(hasTranslation)
		}

		/// Fetches the comment thread for the current article, when a comments
		/// provider serves its URL.
		///
		/// No request is made unless a provider claims the URL, so opening a
		/// regular article never downloads the original page.
		func requestCommentsIfNeeded() {
			guard let articleURL = article?.url else { return }
			guard let provider = CommentsService.shared.provider(for: articleURL) else { return }
			commentsTask = Task { [weak self] in
				let comments = await CommentsService.shared.comments(for: articleURL)
				guard let self, !Task.isCancelled, !comments.isEmpty else { return }
				self.commentsHTML = CommentsHTMLRenderer.html(for: comments, sourceName: provider.displayName)
				guard self.isViewLoaded else { return }
				self.reloadHTMLMaintainingScrollPosition()
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
