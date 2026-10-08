import AppKit
import WebKit
import RSWeb

@MainActor final class RSSHubVerificationViewController: NSViewController, WKNavigationDelegate {
	var onVerified: (() -> Void)?
	private let routeField = NSTextField()
	private let statusLabel = NSTextField(wrappingLabelWithString: "")
	private let checkButton = NSButton()
	private let openButton = NSButton()
	private let webView: WKWebView
	private var feedURL: URL?
	private var verificationTask: Task<Void, Never>?
	private let initialURLString: String

	init(urlString: String = "rsshub://caixin/latest") {
		initialURLString = urlString
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = RSSHubSession.shared.websiteDataStore
		webView = WKWebView(frame: .zero, configuration: configuration)
		super.init(nibName: nil, bundle: nil)
		title = NSLocalizedString("Verify RSSHub Feed", comment: "RSSHub verification")
	}

	required init?(coder: NSCoder) {
		return nil
	}

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
		let instruction = NSTextField(wrappingLabelWithString: NSLocalizedString("Open the feed and complete any browser verification below. Then check that NetNewsWire can download it.", comment: "RSSHub verification"))
		routeField.stringValue = initialURLString
		routeField.setAccessibilityLabel(NSLocalizedString("RSSHub feed address", comment: "RSSHub verification"))
		openButton.title = NSLocalizedString("Open Feed", comment: "RSSHub verification")
		openButton.target = self
		openButton.action = #selector(openFeed(_:))
		checkButton.title = NSLocalizedString("Check Feed and Save Session", comment: "RSSHub verification")
		checkButton.target = self
		checkButton.action = #selector(checkFeed(_:))
		checkButton.isEnabled = false
		let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "RSSHub verification"), target: self, action: #selector(cancel(_:)))
		cancelButton.keyEquivalent = "\u{1b}"
		for button in [openButton, checkButton, cancelButton] { button.bezelStyle = .rounded }
		webView.navigationDelegate = self
		statusLabel.textColor = .secondaryLabelColor
		for subview in [instruction, routeField, openButton, webView, statusLabel, checkButton, cancelButton] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(subview)
		}
		NSLayoutConstraint.activate([
			instruction.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
			instruction.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			instruction.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			routeField.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 12),
			routeField.leadingAnchor.constraint(equalTo: instruction.leadingAnchor),
			routeField.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
			openButton.centerYAnchor.constraint(equalTo: routeField.centerYAnchor),
			openButton.trailingAnchor.constraint(equalTo: instruction.trailingAnchor),
			webView.topAnchor.constraint(equalTo: routeField.bottomAnchor, constant: 12),
			webView.leadingAnchor.constraint(equalTo: instruction.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: instruction.trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),
			statusLabel.leadingAnchor.constraint(equalTo: instruction.leadingAnchor),
			statusLabel.trailingAnchor.constraint(equalTo: instruction.trailingAnchor),
			statusLabel.bottomAnchor.constraint(equalTo: checkButton.topAnchor, constant: -10),
			checkButton.leadingAnchor.constraint(equalTo: instruction.leadingAnchor),
			checkButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
			cancelButton.centerYAnchor.constraint(equalTo: checkButton.centerYAnchor),
			cancelButton.trailingAnchor.constraint(equalTo: instruction.trailingAnchor)
		])
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		openFeed(openButton)
	}

	@objc private func openFeed(_ sender: NSButton) {
		feedURL = nil
		checkButton.isEnabled = false
		let raw = routeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let url = RSSHubResolver().resolvedURL(for: raw) ?? URL(string: raw)
		guard let url, let context = RSSHubSession.shared.context(for: url) else {
			statusLabel.stringValue = NSLocalizedString("Enter a feed address on the configured RSSHub instance.", comment: "RSSHub verification")
			return
		}
		feedURL = url
		statusLabel.stringValue = NSLocalizedString("Complete verification, then check the feed.", comment: "RSSHub verification")
		statusLabel.textColor = .secondaryLabelColor
		checkButton.isEnabled = true
		// Use WebKit's own user agent, rather than the feed reader's default.
		var request = URLRequest(url: url)
		request = context.prepare(request)
		request.setValue(nil, forHTTPHeaderField: "User-Agent")
		webView.load(request)
	}

	@objc private func checkFeed(_ sender: NSButton) {
		guard let feedURL else {
			return
		}
		checkButton.isEnabled = false
		openButton.isEnabled = false
		routeField.isEnabled = false
		statusLabel.stringValue = NSLocalizedString("Checking the feed…", comment: "RSSHub verification")
		verificationTask = Task { [weak self] in
			guard let self else {
				return
			}
			defer {
				checkButton.isEnabled = true
				openButton.isEnabled = true
				routeField.isEnabled = true
			}
			do {
				guard let agent = try await webView.evaluateJavaScript("navigator.userAgent") as? String else {
					throw RSSHubError.unreachable(statusCode: nil)
				}
				try await RSSHubSession.shared.verify(feedURL: feedURL, browserUserAgent: agent)
				try Task.checkCancellation()
				close()
				onVerified?()
			} catch is CancellationError {
				return
			} catch {
				statusLabel.stringValue = NSLocalizedString("NetNewsWire couldn’t download this feed with the browser session. Complete verification and retry, or use another instance.", comment: "RSSHub verification")
				statusLabel.textColor = .systemRed
			}
		}
	}

	@objc private func cancel(_ sender: NSButton) {
		verificationTask?.cancel()
		webView.stopLoading()
		close()
	}

	private func close() {
		if let parent = presentingViewController {
			parent.dismiss(self)
		} else if let window = view.window, let host = window.sheetParent {
			host.endSheet(window)
			window.orderOut(nil)
		}
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
		if navigationAction.targetFrame?.isMainFrame != false,
			let url = navigationAction.request.url,
			RSSHubSession.shared.context(for: url) == nil {
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}
}
