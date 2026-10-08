//
//  RSSHubPreferencesViewControllerTests.swift
//  NetNewsWireTests
//

import AppKit
import Testing
import WebKit
@testable import NetNewsWire

@MainActor
@Suite struct RSSHubPreferencesViewControllerTests {
	@Test("browser verification uses a dedicated cookie store and exposes the feed probe")
	func verificationWindow() throws {
		let controller = RSSHubVerificationViewController()
		controller.loadView()
		let webView = try #require(controller.view.descendants(ofType: WKWebView.self).first)
		let route = try #require(controller.view.descendants(ofType: NSTextField.self).first { $0.stringValue == "rsshub://caixin/latest" })
		let check = try #require(controller.view.descendants(ofType: NSButton.self).first { $0.title == "Check Feed and Save Session" })
		#expect(webView.configuration.websiteDataStore === RSSHubSession.shared.websiteDataStore)
		#expect(webView.configuration.websiteDataStore !== WKWebsiteDataStore.default())
		#expect(!check.isEnabled)
		#expect(route.isEditable)
	}

	@Test("Preferences storyboard resolves the RSSHub pane to the right class")
	func preferencesStoryboardResolvesRSSHubPane() throws {
		let storyboard = try #require(NSStoryboard(name: NSStoryboard.Name("Preferences"), bundle: nil))
		let viewController = try #require(storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("RSSHub")) as? RSSHubPreferencesViewController)
		viewController.loadView()
		viewController.viewDidLoad()
		viewController.view.layoutSubtreeIfNeeded()

		#expect(viewController.view.frame.width > 0)
	}

	@Test("RSSHub preferences document view has a visible size")
	func documentViewHasVisibleSize() throws {
		let viewController = RSSHubPreferencesViewController()
		viewController.loadView()
		viewController.viewDidLoad()
		viewController.view.layoutSubtreeIfNeeded()

		let scrollView = try #require(viewController.view.descendants(ofType: NSScrollView.self).first)
		let documentView = try #require(scrollView.documentView)
		let baseURLField = try #require(documentView.descendants(ofType: NSTextField.self).first { $0.placeholderString == RSSHubSettings.defaultBaseURLString })
		let testButton = try #require(documentView.descendants(ofType: NSButton.self).first { $0.title == "Test Connection" })

		#expect(scrollView.borderType == .noBorder)
		#expect(!scrollView.drawsBackground)
		#expect(documentView.isFlipped)
		#expect(documentView.frame.width > 0)
		#expect(documentView.frame.height > 0)
		#expect(documentView.frame.height >= scrollView.contentView.bounds.height)
		// The document view is flipped, so smaller minY means higher up.
		#expect(baseURLField.frame.minY < testButton.frame.minY)
		#expect(baseURLField.frame.width > 0)
	}

	@Test("RSSHub preferences shows the configured instance address")
	func showsConfiguredInstance() throws {
		let previous = UserDefaults.standard.string(forKey: "rsshub.baseURL")
		UserDefaults.standard.set("rsshub.example.com", forKey: "rsshub.baseURL")
		defer { UserDefaults.standard.set(previous, forKey: "rsshub.baseURL") }

		let viewController = RSSHubPreferencesViewController()
		viewController.loadView()
		viewController.viewDidLoad()

		let baseURLField = try #require(viewController.view.descendants(ofType: NSTextField.self).first { $0.placeholderString == RSSHubSettings.defaultBaseURLString })
		#expect(baseURLField.stringValue == "https://rsshub.example.com")
	}
}

@MainActor
@Suite struct AddFeedSheetNibTests {

	@Test("Add Feed sheet nib connects every outlet the controller declares")
	func nibConnectsOutlets() throws {
		let controller = AddFeedWindowController()
		let nib = try #require(NSNib(nibNamed: "AddFeedSheet", bundle: nil))
		var topLevelObjects: NSArray?
		#expect(nib.instantiate(withOwner: controller, topLevelObjects: &topLevelObjects))

		// A misnamed outlet in the XIB leaves these nil, and opening the sheet in
		// the app would crash.
		#expect(controller.urlTextField != nil)
		#expect(controller.nameTextField != nil)
		#expect(controller.addButton != nil)
		#expect(controller.folderPopupButton != nil)
		#expect(controller.resolvedURLHintLabel != nil)
	}

	@Test("the resolved-URL hint label is hidden and has a font until an rsshub URL is typed")
	func hintLabelStartsHidden() throws {
		let controller = AddFeedWindowController()
		let nib = try #require(NSNib(nibNamed: "AddFeedSheet", bundle: nil))
		var topLevelObjects: NSArray?
		#expect(nib.instantiate(withOwner: controller, topLevelObjects: &topLevelObjects))

		let hint = try #require(controller.resolvedURLHintLabel)
		#expect(hint.isHidden)
		#expect(hint.stringValue.isEmpty)
		// A nil font here is what makes ibtool refuse to open the XIB.
		#expect(hint.font != nil)
	}

	@Test("the hint label appears once an rsshub URL is in the field")
	func hintLabelAppearsForRSSHubURL() throws {
		let controller = AddFeedWindowController()
		let nib = try #require(NSNib(nibNamed: "AddFeedSheet", bundle: nil))
		var topLevelObjects: NSArray?
		#expect(nib.instantiate(withOwner: controller, topLevelObjects: &topLevelObjects))

		controller.urlTextField.stringValue = "rsshub://telegram/channel/zaihuanews"
		controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.urlTextField))

		let hint = try #require(controller.resolvedURLHintLabel)
		#expect(hint.isHidden == false)
		#expect(hint.stringValue.contains("https://rsshub.app/telegram/channel/zaihuanews"))
		#expect(hint.toolTip == "https://rsshub.app/telegram/channel/zaihuanews")
	}
}

private extension NSView {

	func descendants<T: NSView>(ofType type: T.Type) -> [T] {
		var found: [T] = []
		if let view = self as? T {
			found.append(view)
		}
		for subview in subviews {
			found.append(contentsOf: subview.descendants(ofType: type))
		}
		return found
	}
}
