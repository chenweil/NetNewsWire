//
//  TranslationPreferencesViewControllerTests.swift
//  NetNewsWireTests
//

import AppKit
import Testing
@testable import NetNewsWire

@MainActor
@Suite struct TranslationPreferencesViewControllerTests {

	@Test("translation preferences document view has a visible size")
	func documentViewHasVisibleSize() throws {
		let viewController = TranslationPreferencesViewController()
		viewController.loadView()
		viewController.viewDidLoad()
		viewController.view.layoutSubtreeIfNeeded()

		let scrollView = try #require(viewController.view.firstDescendant(ofType: NSScrollView.self))
		let documentView = try #require(scrollView.documentView)
		let enableButton = try #require(documentView.firstDescendant(NSButton.self, title: "Enable Translation"))

		#expect(scrollView.borderType == .noBorder)
		#expect(!scrollView.drawsBackground)
		#expect(documentView.isFlipped)
		#expect(documentView.frame.width > 0)
		#expect(documentView.frame.height > 0)
		#expect(documentView.frame.height >= scrollView.contentView.bounds.height)
		#expect(enableButton.frame.minY < 60)
	}
}

private extension NSView {

	func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
		if let view = self as? T {
			return view
		}
		for subview in subviews {
			if let view = subview.firstDescendant(ofType: type) {
				return view
			}
		}
		return nil
	}

	func firstDescendant(_ type: NSButton.Type, title: String) -> NSButton? {
		if let button = self as? NSButton, button.title == title {
			return button
		}
		for subview in subviews {
			if let button = subview.firstDescendant(type, title: title) {
				return button
			}
		}
		return nil
	}
}
