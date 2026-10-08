//
//  AddFeedController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/28/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import AppKit
import RSCore
import RSCoreResources
import RSTree
import Articles
import Account
import RSParser

// Run add-feed sheet.
// If it returns with URL and optional name,
//   run FeedFinder plus modal progress window.
//   If FeedFinder returns feed,
//      add feed.
//   Else,
//      display error sheet.

@MainActor final class AddFeedController: AddFeedWindowControllerDelegate {
	private let hostWindow: NSWindow
	private var addFeedWindowController: AddFeedWindowController?
	private var foundFeedURLString: String?
	private var titleFromFeed: String?
	private var attemptedBrowserVerification = false
	private var verificationWindow: NSWindow?

	init(hostWindow: NSWindow) {
		self.hostWindow = hostWindow
	}

	func showAddFeedSheet(_ urlString: String? = nil, _ name: String? = nil, _ account: Account? = nil, _ folder: Folder? = nil) {
		attemptedBrowserVerification = false
		let folderTreeControllerDelegate = FolderTreeControllerDelegate()
		let folderTreeController = TreeController(delegate: folderTreeControllerDelegate)

		let windowController = AddFeedWindowController(urlString: urlString ?? urlStringFromPasteboard,
													   name: name,
													   account: account,
													   folder: folder,
													   folderTreeController: folderTreeController,
													   delegate: self)
		addFeedWindowController = windowController
		windowController.runSheetOnWindow(hostWindow)
	}

	// MARK: - AddFeedWindowControllerDelegate

	func addFeedWindowController(_: AddFeedWindowController, userEnteredURL url: URL, userEnteredTitle title: String?, container: Container) {
		closeAddFeedSheet(NSApplication.ModalResponse.OK)

		guard let accountAndFolderSpecifier = accountAndFolderFromContainer(container) else {
			return
		}
		let account = accountAndFolderSpecifier.account
		let resolvedURL = RSSHubResolver().resolvedURL(for: url.absoluteString) ?? url

		if account.hasFeed(withURL: resolvedURL.absoluteString) {
			showAlreadySubscribedError(resolvedURL.absoluteString)
			return
		}

		beginShowingProgress()
		account.createFeed(url: url.absoluteString, name: title, container: container, validateFeed: true) { result in

			self.endShowingProgress()

			switch result {
			case .success(let feed):
				NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
			case .failure(let error):
				// Convert only when the user actually typed a rsshub:// URL;
				// plain feeds that happen to live on the instance host keep
				// their original errors.
				let presentedError = RSSHubError.subscriptionFailure(forUserEnteredURL: url.absoluteString, underlying: error) ?? error
				if let rssHubError = presentedError as? RSSHubError,
					!self.attemptedBrowserVerification,
					account.type == .onMyMac || account.type == .cloudKit {
					switch rssHubError {
					case .accessDenied, .browserVerificationRequired:
						self.attemptedBrowserVerification = true
						let controller = RSSHubVerificationViewController(urlString: url.absoluteString)
						controller.onVerified = { [weak self] in
							guard let self, let addFeedWindowController = self.addFeedWindowController else {
								return
								}
							self.addFeedWindowController(addFeedWindowController, userEnteredURL: url, userEnteredTitle: title, container: container)
						}
						let window = NSWindow(contentViewController: controller)
						window.title = NSLocalizedString("Verify RSSHub Feed", comment: "RSSHub verification")
						self.verificationWindow = window
						DispatchQueue.main.async {
							self.hostWindow.beginSheet(window) { [weak self] _ in
								self?.verificationWindow = nil
							}
						}
						return
					default:
						break
					}
				}
				switch presentedError {
				case AccountError.createErrorAlreadySubscribed:
					self.showAlreadySubscribedError(resolvedURL.absoluteString)
				case AccountError.createErrorNotFound:
					self.showNoFeedsErrorMessage()
				default:
					DispatchQueue.main.async {
						NSApplication.shared.presentError(presentedError)
					}
				}
			}

		}

	}

	func addFeedWindowControllerUserDidCancel(_: AddFeedWindowController) {
		closeAddFeedSheet(NSApplication.ModalResponse.cancel)
	}
}

private extension AddFeedController {
	var urlStringFromPasteboard: String? {
		if let urlString = NSPasteboard.urlString(from: NSPasteboard.general) {
			return urlString.normalizedURL
		}
		return nil
	}

	struct AccountAndFolderSpecifier {
		let account: Account
		let folder: Folder?
	}

	func accountAndFolderFromContainer(_ container: Container) -> AccountAndFolderSpecifier? {
		if let account = container as? Account {
			return AccountAndFolderSpecifier(account: account, folder: nil)
		}
		if let folder = container as? Folder, let account = folder.account {
			return AccountAndFolderSpecifier(account: account, folder: folder)
		}
		return nil
	}

	func closeAddFeedSheet(_ returnCode: NSApplication.ModalResponse) {
		if let sheetWindow = addFeedWindowController?.window, sheetWindow.sheetParent === hostWindow {
			hostWindow.endSheet(sheetWindow, returnCode: returnCode)
		}
	}

	// MARK: - Errors

	func showAlreadySubscribedError(_ urlString: String) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = NSLocalizedString("Already subscribed", comment: "Feed finder")
		alert.informativeText = NSLocalizedString("Can’t add this feed because you’ve already subscribed to it.", comment: "Feed finder")
		alert.beginSheetModal(for: hostWindow)
	}

	func showInitialDownloadError(_ error: Error) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = NSLocalizedString("Download Error", comment: "Feed finder")

		let formatString = NSLocalizedString("Can’t add this feed because of a download error: “%@”", comment: "Feed finder")
		let errorText = NSString.localizedStringWithFormat(formatString as NSString, error.localizedDescription)
		alert.informativeText = errorText as String
		alert.beginSheetModal(for: hostWindow)
	}

	func showNoFeedsErrorMessage() {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = NSLocalizedString("Feed not found", comment: "Feed finder")
		alert.informativeText = NSLocalizedString("Can’t add a feed because no feed was found.", comment: "Feed finder")
		alert.beginSheetModal(for: hostWindow)
	}

	// MARK: - Progress

	func beginShowingProgress() {
		IndeterminateProgressController.beginProgressWithMessage(NSLocalizedString("Finding feed…", comment: "Feed finder"), for: hostWindow)
	}

	func endShowingProgress() {
		IndeterminateProgressController.endProgress()
		hostWindow.makeKeyAndOrderFront(self)
	}
}
