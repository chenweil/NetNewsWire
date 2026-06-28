//
//  TranslationPreferencesViewController.swift
//  NetNewsWire
//
//  Translation preferences UI for configuring translation engine,
//  target language, and OpenAI-compatible API settings.
//

import AppKit
import Secrets
import os

private final class TranslationPreferencesDocumentView: NSView {
	override var isFlipped: Bool {
		true
	}
}

/// Preferences view controller for translation settings.
/// Provides UI for enabling/disabling translation, selecting target language,
/// choosing translation engine, and configuring OpenAI-compatible API.
final class TranslationPreferencesViewController: NSViewController {

	// MARK: - UI Components

	private let scrollView = NSScrollView()
	private let contentView = TranslationPreferencesDocumentView()

	// Enable section
	private let enableCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

	// Target language section
	private let targetLanguageLabel = NSTextField(labelWithString: "")
	private let targetLanguagePopup = NSPopUpButton()

	// Engine section
	private let engineLabel = NSTextField(labelWithString: "")
	private let engineSegmentedControl = NSSegmentedControl()

	// Skip when source matches target
	private let skipCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

	// OpenAI settings section
	private let openAIBox = NSBox()
	private let baseURLLabel = NSTextField(labelWithString: "")
	private let baseURLField = NSTextField()
	private let apiKeyLabel = NSTextField(labelWithString: "")
	private let apiKeyField = NSSecureTextField()
	private let modelLabel = NSTextField(labelWithString: "")
	private let modelField = NSTextField()
	private let testConnectionButton = NSButton()
	private let apiKeyStatusField = NSTextField(labelWithString: "")

	// MARK: - Properties

	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TranslationPreferences")
	private var isUpdatingUI = false

	// Constants for Keychain storage (must match TranslationCoordinator)
	private static let translationServer = "translation.openai-compatible"
	private static let translationUsername = "api-key"

	// MARK: - Lifecycle

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 500))
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

	@objc func enableCheckboxChanged(_ sender: NSButton) {
		guard !isUpdatingUI else { return }
		UserDefaults.standard.set(sender.state == .on, forKey: "translation.enabled")
		updateUI()
	}

	@objc func targetLanguageChanged(_ sender: NSPopUpButton) {
		guard !isUpdatingUI else { return }
		if let languageCode = sender.selectedItem?.representedObject as? String {
			UserDefaults.standard.set(languageCode, forKey: "translation.targetLanguage")
		}
	}

	@objc func engineChanged(_ sender: NSSegmentedControl) {
		guard !isUpdatingUI else { return }
		let choice: String
		switch sender.selectedSegment {
		case 0:
			choice = "apple"
		case 1:
			choice = "openai_compatible"
		default:
			choice = "apple"
		}
		UserDefaults.standard.set(choice, forKey: "translation.engine")
		updateUI()
	}

	@objc func skipCheckboxChanged(_ sender: NSButton) {
		guard !isUpdatingUI else { return }
		UserDefaults.standard.set(sender.state == .on, forKey: "translation.skipWhenSourceMatchesTarget")
	}

	@objc func baseURLChanged(_ sender: NSTextField) {
		guard !isUpdatingUI else { return }
		let stringValue = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		// Validate URL format
		guard let url = URL(string: stringValue),
			  url.scheme?.hasPrefix("http") == true else {
			showErrorMessage("Invalid URL format. Must be http:// or https://")
			return
		}
		UserDefaults.standard.set(stringValue, forKey: "translation.openAI.baseURL")
	}

	@objc func apiKeyChanged(_ sender: NSSecureTextField) {
		guard !isUpdatingUI else { return }
		let apiKey = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		saveAPIKey(apiKey)
		updateAPIKeyStatus()
	}

	@objc func modelChanged(_ sender: NSTextField) {
		guard !isUpdatingUI else { return }
		let model = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !model.isEmpty else { return }
		UserDefaults.standard.set(model, forKey: "translation.openAI.model")
	}

	@objc func testConnectionClicked(_ sender: NSButton) {
		guard saveOpenAISettingsFromFields() else {
			return
		}
		testOpenAIConnection()
	}
}

// MARK: - UI Setup

private extension TranslationPreferencesViewController {

	func setupUI() {
		title = "Translation"

		// Main scroll view
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false

		contentView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = contentView

		view.addSubview(scrollView)

		setupEnableSection()
		setupTargetLanguageSection()
		setupEngineSection()
		setupSkipSection()
		setupOpenAISection()

		// Layout all sections
		layoutSections()
		layoutDocumentView()

		// Activate scroll view constraints
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
		])
	}

	func layoutDocumentView() {
		let padding: CGFloat = 20

		NSLayoutConstraint.activate([
			contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
			contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
			contentView.bottomAnchor.constraint(greaterThanOrEqualTo: openAIBox.bottomAnchor, constant: padding),
		])
	}

	func setupEnableSection() {
		enableCheckbox.title = "Enable Translation"
		enableCheckbox.target = self
		enableCheckbox.action = #selector(enableCheckboxChanged(_:))
		enableCheckbox.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(enableCheckbox)
	}

	func setupTargetLanguageSection() {
		targetLanguageLabel.stringValue = "Target Language:"
		targetLanguageLabel.alignment = .right
		targetLanguageLabel.translatesAutoresizingMaskIntoConstraints = false

		targetLanguagePopup.target = self
		targetLanguagePopup.action = #selector(targetLanguageChanged(_:))
		targetLanguagePopup.translatesAutoresizingMaskIntoConstraints = false
		populateTargetLanguages()

		contentView.addSubview(targetLanguageLabel)
		contentView.addSubview(targetLanguagePopup)
	}

	func setupEngineSection() {
		engineLabel.stringValue = "Translation Engine:"
		engineLabel.alignment = .right
		engineLabel.translatesAutoresizingMaskIntoConstraints = false

		engineSegmentedControl.segmentStyle = .texturedRounded
		engineSegmentedControl.segmentCount = 2
		engineSegmentedControl.setLabel("Apple", forSegment: 0)
		engineSegmentedControl.setLabel("OpenAI-Compatible", forSegment: 1)
		engineSegmentedControl.target = self
		engineSegmentedControl.action = #selector(engineChanged(_:))
		engineSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(engineLabel)
		contentView.addSubview(engineSegmentedControl)
	}

	func setupSkipSection() {
		skipCheckbox.title = "Skip translation when article is already in target language"
		skipCheckbox.target = self
		skipCheckbox.action = #selector(skipCheckboxChanged(_:))
		skipCheckbox.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(skipCheckbox)
	}

	func setupOpenAISection() {
		openAIBox.title = "OpenAI-Compatible Settings"
		openAIBox.titlePosition = .atTop
		openAIBox.translatesAutoresizingMaskIntoConstraints = false

		// Base URL
		baseURLLabel.stringValue = "Base URL:"
		baseURLLabel.alignment = .right
		baseURLLabel.translatesAutoresizingMaskIntoConstraints = false

		baseURLField.placeholderString = "https://api.openai.com/v1/"
		baseURLField.target = self
		baseURLField.action = #selector(baseURLChanged(_:))
		baseURLField.translatesAutoresizingMaskIntoConstraints = false

		// API Key
		apiKeyLabel.stringValue = "API Key:"
		apiKeyLabel.alignment = .right
		apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false

		apiKeyField.placeholderString = "sk-..."
		apiKeyField.target = self
		apiKeyField.action = #selector(apiKeyChanged(_:))
		apiKeyField.translatesAutoresizingMaskIntoConstraints = false

		apiKeyStatusField.textColor = .secondaryLabelColor
		apiKeyStatusField.translatesAutoresizingMaskIntoConstraints = false

		// Model
		modelLabel.stringValue = "Model:"
		modelLabel.alignment = .right
		modelLabel.translatesAutoresizingMaskIntoConstraints = false

		modelField.placeholderString = "gpt-4o-mini"
		modelField.target = self
		modelField.action = #selector(modelChanged(_:))
		modelField.translatesAutoresizingMaskIntoConstraints = false

		// Test Connection button
		testConnectionButton.title = "Test Connection"
		testConnectionButton.bezelStyle = .rounded
		testConnectionButton.target = self
		testConnectionButton.action = #selector(testConnectionClicked(_:))
		testConnectionButton.translatesAutoresizingMaskIntoConstraints = false

		// Add to box
		let boxContentView = openAIBox.contentView
		boxContentView?.addSubview(baseURLLabel)
		boxContentView?.addSubview(baseURLField)
		boxContentView?.addSubview(apiKeyLabel)
		boxContentView?.addSubview(apiKeyField)
		boxContentView?.addSubview(apiKeyStatusField)
		boxContentView?.addSubview(modelLabel)
		boxContentView?.addSubview(modelField)
		boxContentView?.addSubview(testConnectionButton)

		contentView.addSubview(openAIBox)
	}

	func populateTargetLanguages() {
		let menu = targetLanguagePopup.menu!
		menu.removeAllItems()

		// Common languages with BCP-47 codes
		let languages = [
			("English", "en"),
			("简体中文", "zh-Hans"),
			("繁體中文", "zh-Hant"),
			("日本語", "ja"),
			("한국어", "ko"),
			("Español", "es"),
			("Français", "fr"),
			("Deutsch", "de"),
			("Italiano", "it"),
			("Português", "pt"),
			("Русский", "ru"),
			("العربية", "ar"),
			("हिन्दी", "hi"),
		]

		for (name, code) in languages {
			let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
			item.representedObject = code
			menu.addItem(item)
		}
	}

	func layoutSections() {
		let padding: CGFloat = 20
		let labelWidth: CGFloat = 120
		let fieldSpacing: CGFloat = 8
		let rowSpacing: CGFloat = 14

		// Enable checkbox at top
		NSLayoutConstraint.activate([
			enableCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
			enableCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
		])

		// Target language
		NSLayoutConstraint.activate([
			targetLanguageLabel.topAnchor.constraint(equalTo: enableCheckbox.bottomAnchor, constant: padding),
			targetLanguageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
			targetLanguageLabel.widthAnchor.constraint(equalToConstant: labelWidth),

			targetLanguagePopup.centerYAnchor.constraint(equalTo: targetLanguageLabel.centerYAnchor),
			targetLanguagePopup.leadingAnchor.constraint(equalTo: targetLanguageLabel.trailingAnchor, constant: fieldSpacing),
			targetLanguagePopup.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),
		])

		// Engine
		NSLayoutConstraint.activate([
			engineLabel.topAnchor.constraint(equalTo: targetLanguageLabel.bottomAnchor, constant: padding),
			engineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
			engineLabel.widthAnchor.constraint(equalToConstant: labelWidth),

			engineSegmentedControl.centerYAnchor.constraint(equalTo: engineLabel.centerYAnchor),
			engineSegmentedControl.leadingAnchor.constraint(equalTo: engineLabel.trailingAnchor, constant: fieldSpacing),
		])

		// Skip checkbox
		NSLayoutConstraint.activate([
			skipCheckbox.topAnchor.constraint(equalTo: engineLabel.bottomAnchor, constant: padding),
			skipCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
			skipCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),
		])

		// OpenAI box
		NSLayoutConstraint.activate([
			openAIBox.topAnchor.constraint(equalTo: skipCheckbox.bottomAnchor, constant: padding),
			openAIBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
			openAIBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
		])

		// Inside OpenAI box
		guard let boxContentView = openAIBox.contentView else { return }

		let boxPadding: CGFloat = 12

		// Base URL
		NSLayoutConstraint.activate([
			baseURLLabel.topAnchor.constraint(equalTo: boxContentView.topAnchor, constant: boxPadding),
			baseURLLabel.leadingAnchor.constraint(equalTo: boxContentView.leadingAnchor, constant: boxPadding),
			baseURLLabel.widthAnchor.constraint(equalToConstant: labelWidth - boxPadding),

			baseURLField.centerYAnchor.constraint(equalTo: baseURLLabel.centerYAnchor),
			baseURLField.leadingAnchor.constraint(equalTo: baseURLLabel.trailingAnchor, constant: fieldSpacing),
			baseURLField.trailingAnchor.constraint(equalTo: boxContentView.trailingAnchor, constant: -boxPadding),
		])

		// API Key
		NSLayoutConstraint.activate([
			apiKeyLabel.topAnchor.constraint(equalTo: baseURLLabel.bottomAnchor, constant: rowSpacing),
			apiKeyLabel.leadingAnchor.constraint(equalTo: boxContentView.leadingAnchor, constant: boxPadding),
			apiKeyLabel.widthAnchor.constraint(equalToConstant: labelWidth - boxPadding),

			apiKeyField.centerYAnchor.constraint(equalTo: apiKeyLabel.centerYAnchor),
			apiKeyField.leadingAnchor.constraint(equalTo: apiKeyLabel.trailingAnchor, constant: fieldSpacing),
			apiKeyField.trailingAnchor.constraint(equalTo: boxContentView.trailingAnchor, constant: -boxPadding),

			apiKeyStatusField.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 4),
			apiKeyStatusField.leadingAnchor.constraint(equalTo: apiKeyField.leadingAnchor),
		])

		// Model
		NSLayoutConstraint.activate([
			modelLabel.topAnchor.constraint(equalTo: apiKeyStatusField.bottomAnchor, constant: rowSpacing),
			modelLabel.leadingAnchor.constraint(equalTo: boxContentView.leadingAnchor, constant: boxPadding),
			modelLabel.widthAnchor.constraint(equalToConstant: labelWidth - boxPadding),

			modelField.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),
			modelField.leadingAnchor.constraint(equalTo: modelLabel.trailingAnchor, constant: fieldSpacing),
			modelField.trailingAnchor.constraint(equalTo: boxContentView.trailingAnchor, constant: -boxPadding),
		])

		// Test button
		NSLayoutConstraint.activate([
			testConnectionButton.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: padding),
			testConnectionButton.leadingAnchor.constraint(equalTo: modelLabel.trailingAnchor, constant: fieldSpacing),
			testConnectionButton.bottomAnchor.constraint(equalTo: boxContentView.bottomAnchor, constant: -boxPadding),
		])
	}
}

// MARK: - UI Updates

private extension TranslationPreferencesViewController {

	func updateUI() {
		isUpdatingUI = true
		defer { isUpdatingUI = false }

		let defaults = UserDefaults.standard

		// Enable checkbox
		enableCheckbox.state = defaults.bool(forKey: "translation.enabled") ? .on : .off

		// Target language
		if let targetLanguage = defaults.string(forKey: "translation.targetLanguage") {
			for item in targetLanguagePopup.menu?.items ?? [] {
				if item.representedObject as? String == targetLanguage {
					targetLanguagePopup.select(item)
					break
				}
			}
		}

		// Engine
		let engine = defaults.string(forKey: "translation.engine") ?? "apple"
		engineSegmentedControl.selectedSegment = (engine == "openai_compatible") ? 1 : 0

		// Skip checkbox
		if defaults.object(forKey: "translation.skipWhenSourceMatchesTarget") == nil {
			skipCheckbox.state = .on // Default to true
		} else {
			skipCheckbox.state = defaults.bool(forKey: "translation.skipWhenSourceMatchesTarget") ? .on : .off
		}

		// OpenAI settings
		let baseURL = defaults.string(forKey: "translation.openAI.baseURL") ?? "https://api.openai.com/v1/"
		baseURLField.stringValue = baseURL

		let model = defaults.string(forKey: "translation.openAI.model") ?? "gpt-4o-mini"
		modelField.stringValue = model

		// API key status
		updateAPIKeyStatus()
	}

	func updateAPIKeyStatus() {
		if let creds = try? CredentialsManager.retrieveCredentials(
			type: .openAICompatibleAPIKey,
			server: Self.translationServer,
			username: Self.translationUsername
		), !creds.secret.isEmpty {
			apiKeyStatusField.stringValue = "API key configured"
			apiKeyStatusField.textColor = NSColor.systemGreen
			apiKeyField.stringValue = creds.secret // Show the key
		} else {
			apiKeyStatusField.stringValue = "No API key configured"
			apiKeyStatusField.textColor = NSColor.secondaryLabelColor
			apiKeyField.stringValue = ""
		}
	}

	@discardableResult func saveAPIKey(_ apiKey: String) -> Bool {
		do {
			if apiKey.isEmpty {
				// Remove the key
				try CredentialsManager.removeCredentials(
					type: .openAICompatibleAPIKey,
					server: Self.translationServer,
					username: Self.translationUsername
				)
			} else {
				// Store the key
				let credentials = Credentials(
					type: .openAICompatibleAPIKey,
					username: Self.translationUsername,
					secret: apiKey
				)
				try CredentialsManager.storeCredentials(credentials, server: Self.translationServer)
			}
			logger.info("API key saved successfully")
			return true
		} catch {
			logger.error("Failed to save API key: \(error.localizedDescription)")
			showErrorMessage("Failed to save API key: \(error.localizedDescription)")
			return false
		}
	}

	func saveOpenAISettingsFromFields() -> Bool {
		let baseURLString = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: baseURLString),
			  url.scheme?.hasPrefix("http") == true else {
			showErrorMessage("Invalid URL format. Must be http:// or https://")
			return false
		}
		UserDefaults.standard.set(url.absoluteString, forKey: "translation.openAI.baseURL")

		let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !model.isEmpty else {
			showErrorMessage("Model is required.")
			return false
		}
		UserDefaults.standard.set(model, forKey: "translation.openAI.model")

		let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard saveAPIKey(apiKey) else {
			return false
		}
		updateAPIKeyStatus()

		return true
	}

	func showErrorMessage(_ message: String) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = "Error"
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}
}

// MARK: - Test Connection

private extension TranslationPreferencesViewController {

	func testOpenAIConnection() {
		testConnectionButton.isEnabled = false
		testConnectionButton.title = "Testing..."

		Task { @MainActor in
			defer {
				testConnectionButton.isEnabled = true
				testConnectionButton.title = "Test Connection"
			}

			do {
				let settings = TranslationSettings()
				let config = OpenAICompatibleEngine.Config(
					baseURL: settings.openAIBaseURL,
					apiKey: try await getAPIKey(),
					model: settings.openAIModel
				)

				// Test with a simple translation request
				let request = TranslationRequest(
					articleID: "test",
					title: "Hello",
					bodyHTML: "<p>World</p>",
					targetLanguage: "zh-Hans",
					bodySource: .feedBody
				)

				let engine = OpenAICompatibleEngine.live(config: config)
				_ = try await engine.translate(request)

				showSuccessMessage("Connection successful!")
			} catch {
				showErrorMessage("Connection failed: \(error.localizedDescription)")
			}
		}
	}

	func getAPIKey() async throws -> String {
		guard let creds = try CredentialsManager.retrieveCredentials(
			type: .openAICompatibleAPIKey,
			server: Self.translationServer,
			username: Self.translationUsername
		) else {
			throw TranslationError.credentialsMissing
		}
		return creds.secret
	}

	func showSuccessMessage(_ message: String) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = "Success"
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}
}
