//
//  IndeterminateProgressWindowController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/28/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

#if os(macOS)
import AppKit

@MainActor public final class IndeterminateProgressController {
	private static var windowController: IndeterminateProgressWindowController?
	private static var runningProgressWindow = false

	public static func beginProgressWithMessage(_ message: String, for hostWindow: NSWindow? = nil) {
		if runningProgressWindow {
			assertionFailure("Expected !runningProgressWindow.")
			endProgress()
		}

		runningProgressWindow = true
		windowController = IndeterminateProgressWindowController(message: message)
		guard let window = windowController?.window else {
			runningProgressWindow = false
			windowController = nil
			return
		}
		if let hostWindow {
			// A Swift task must return to its executor so the download task can
			// run. A sheet blocks window input without entering a nested runModal.
			hostWindow.beginSheet(window)
		} else {
			NSApplication.shared.runModal(for: window)
		}
	}

	public static func endProgress() {
		if !runningProgressWindow {
			assertionFailure("Expected runningProgressWindow.")
			return
		}

		runningProgressWindow = false
		if let window = windowController?.window, let hostWindow = window.sheetParent {
			hostWindow.endSheet(window)
		} else {
			NSApplication.shared.stopModal()
		}
		windowController?.close()
		windowController = nil
	}
}

private final class IndeterminateProgressWindowController: NSWindowController {
	@IBOutlet var messageLabel: NSTextField!
	@IBOutlet var progressIndicator: NSProgressIndicator!
	@objc dynamic var message = ""

	convenience init(message: String) {
        self.init(window: nil)
		self.message = message
        Bundle.module.loadNibNamed("IndeterminateProgressWindow", owner: self, topLevelObjects: nil)
	}

	override func windowDidLoad() {
		progressIndicator.startAnimation(self)
	}
}
#endif
