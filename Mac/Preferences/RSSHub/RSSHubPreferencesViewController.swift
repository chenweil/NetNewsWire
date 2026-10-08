//
//  RSSHubPreferencesViewController.swift
//  NetNewsWire
//

import AppKit
import os
import RSWeb

private final class RSSHubPreferencesDocumentView: NSView {
	override var isFlipped: Bool {
		true
	}
}

/// Preferences pane for the RSSHub instance used to expand `rsshub://` URLs.
final class RSSHubPreferencesViewController: NSViewController, NSTextFieldDelegate {

	private let scrollView = NSScrollView()
	private let contentView = RSSHubPreferencesDocumentView()

	private let explanationLabel = NSTextField(wrappingLabelWithString: "")
	private let baseURLLabel = NSTextField(labelWithString: "")
	private let baseURLField = NSTextField()
	private let accessKeyLabel = NSTextField(labelWithString: "")
	private let accessKeyField = NSSecureTextField()
	private let testButton = NSButton()
	private let verifyButton = NSButton()
	private let statusLabel = NSTextField(labelWithString: "")

	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RSSHubPreferences")
	private var isUpdatingUI = false

	private let settings = RSSHubSettings.shared

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 320))
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setupUI()
		updateUI()
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		updateUI()
	}

	// MARK: - Actions
	@objc private func verifyFeedClicked(_ sender: NSButton) {
		guard saveFields() else {
			return
		}
		let controller = RSSHubVerificationViewController()
		controller.onVerified = { [weak self] in
			self?.statusLabel.stringValue = NSLocalizedString("Feed verified. The session will be used for subscriptions and refreshes on this device.", comment: "RSSHub verification")
			self?.statusLabel.textColor = .systemGreen
		}
		presentAsSheet(controller)
	}

	@objc private func fieldEndedEditing(_ notification: Notification) {
		guard saveFields() else { return }
		updateUI()
	}

	@objc private func testConnectionClicked(_ sender: NSButton) {
		guard saveFields() else { return }

		testButton.isEnabled = false
		statusLabel.stringValue = NSLocalizedString("Testing…", comment: "RSSHub preferences")
		statusLabel.textColor = .secondaryLabelColor

		guard let healthURL = settings.baseURL?.appendingPathComponent("healthz") else {
			testButton.isEnabled = true
			return
		}
		Task {
			var status = ""
			var isSuccess = false
			do {
				let result = try await Downloader.shared.download(healthURL)
				let response = result.response
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
				isSuccess = (200..<300).contains(statusCode)
				if isSuccess {
					status = NSLocalizedString("Instance is reachable.", comment: "RSSHub preferences")
				} else if statusCode == 403 {
					status = NSLocalizedString("Instance rejected the request. Public instances often refuse non-browser clients.", comment: "RSSHub preferences")
				} else if statusCode == 404 {
					status = NSLocalizedString("No health endpoint — the instance may not be an RSSHub server.", comment: "RSSHub preferences")
				} else {
					status = NSLocalizedString("Unexpected response: HTTP \(statusCode).", comment: "RSSHub preferences")
				}
			} catch {
				status = NSLocalizedString("Couldn’t reach the instance.", comment: "RSSHub preferences")
				logger.error("RSSHubPreferences: health check failed: \(error.localizedDescription)")
			}

			await MainActor.run {
				self.testButton.isEnabled = true
				self.statusLabel.stringValue = status
				self.statusLabel.textColor = isSuccess ? .systemGreen : .systemRed
			}
		}
	}

	// MARK: - Saving

	@discardableResult
	private func saveFields() -> Bool {
		guard !isUpdatingUI else { return true }

		let baseURLInput = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if baseURLInput.isEmpty {
			settings.resetBaseURL()
		} else if settings.setBaseURLString(baseURLInput) == nil {
			statusLabel.stringValue = NSLocalizedString("The instance address isn’t a valid http or https URL.", comment: "RSSHub preferences")
			statusLabel.textColor = .systemRed
			return false
		}

		do {
			try settings.setAccessKey(accessKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
		} catch {
			statusLabel.stringValue = NSLocalizedString("Couldn’t save the access key.", comment: "RSSHub preferences")
			statusLabel.textColor = .systemRed
			logger.error("RSSHubPreferences: couldn’t save access key: \(error.localizedDescription)")
			return false
		}

		if !statusLabel.stringValue.isEmpty {
			statusLabel.stringValue = ""
		}
		return true
	}

	// MARK: - UI

	private func setupUI() {
		scrollView.documentView = contentView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		contentView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(scrollView)

		explanationLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
		explanationLabel.textColor = .secondaryLabelColor
		explanationLabel.stringValue = NSLocalizedString("NetNewsWire expands rsshub:// URLs into real feed addresses using this instance, so rsshub://telegram/channel/somechannel becomes <instance>/telegram/channel/somechannel. The official demo instance is rate-limited and often refuses non-browser clients, so a self-hosted instance is more reliable.", comment: "RSSHub preferences explanation")

		baseURLLabel.stringValue = NSLocalizedString("Instance address:", comment: "RSSHub preferences")
		baseURLField.placeholderString = RSSHubSettings.defaultBaseURLString
		baseURLField.delegate = self
		baseURLField.target = self
		baseURLField.action = #selector(fieldEndedEditing(_:))
		baseURLField.setAccessibilityLabel(baseURLLabel.stringValue)

		accessKeyLabel.stringValue = NSLocalizedString("Access key (optional):", comment: "RSSHub preferences")
		accessKeyField.placeholderString = NSLocalizedString("Only if the instance requires one", comment: "RSSHub preferences")
		accessKeyField.delegate = self
		accessKeyField.target = self
		accessKeyField.action = #selector(fieldEndedEditing(_:))
		accessKeyField.setAccessibilityLabel(accessKeyLabel.stringValue)

		testButton.title = NSLocalizedString("Test Connection", comment: "RSSHub preferences")
		testButton.bezelStyle = .rounded
		testButton.target = self
		testButton.action = #selector(testConnectionClicked(_:))
		verifyButton.title = NSLocalizedString("Verify Feed in Browser…", comment: "RSSHub verification")
		verifyButton.bezelStyle = .rounded
		verifyButton.target = self
		verifyButton.action = #selector(verifyFeedClicked(_:))

		statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.textColor = .secondaryLabelColor

		for subview in [explanationLabel, baseURLLabel, baseURLField, accessKeyLabel, accessKeyField, testButton, verifyButton, statusLabel] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(subview)
		}

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

			// The document view has to be pinned to the clip view, or it never gets
			// a width and every constraint inside it is unsolvable.
			contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
			contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

			explanationLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
			explanationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
			explanationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

			baseURLLabel.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: 24),
			baseURLLabel.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			baseURLLabel.trailingAnchor.constraint(lessThanOrEqualTo: explanationLabel.trailingAnchor),

			baseURLField.topAnchor.constraint(equalTo: baseURLLabel.bottomAnchor, constant: 6),
			baseURLField.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			baseURLField.trailingAnchor.constraint(equalTo: explanationLabel.trailingAnchor),

			accessKeyLabel.topAnchor.constraint(equalTo: baseURLField.bottomAnchor, constant: 18),
			accessKeyLabel.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			accessKeyLabel.trailingAnchor.constraint(lessThanOrEqualTo: explanationLabel.trailingAnchor),

			accessKeyField.topAnchor.constraint(equalTo: accessKeyLabel.bottomAnchor, constant: 6),
			accessKeyField.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			accessKeyField.trailingAnchor.constraint(equalTo: explanationLabel.trailingAnchor),

			testButton.topAnchor.constraint(equalTo: accessKeyField.bottomAnchor, constant: 20),
			testButton.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			verifyButton.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
			verifyButton.leadingAnchor.constraint(equalTo: testButton.trailingAnchor, constant: 8),
			verifyButton.trailingAnchor.constraint(lessThanOrEqualTo: explanationLabel.trailingAnchor),

			statusLabel.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 8),
			statusLabel.leadingAnchor.constraint(equalTo: explanationLabel.leadingAnchor),
			statusLabel.trailingAnchor.constraint(equalTo: explanationLabel.trailingAnchor),
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: statusLabel.bottomAnchor, constant: 20)
		])
	}

	private func updateUI() {
		isUpdatingUI = true
		baseURLField.stringValue = settings.baseURLString
		accessKeyField.stringValue = settings.accessKey ?? ""
		statusLabel.stringValue = ""
		isUpdatingUI = false
	}
}
