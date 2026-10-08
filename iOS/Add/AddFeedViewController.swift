//
//  AddFeedViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/16/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Account
import RSCore
import RSTree
import RSParser

final class AddFeedViewController: UITableViewController {
	@IBOutlet var addButton: UIBarButtonItem!
	@IBOutlet var urlTextField: UITextField!
	@IBOutlet var urlTextFieldToSuperViewConstraint: NSLayoutConstraint!
	@IBOutlet var nameTextField: UITextField!

	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 400.0)

	private var folderLabel = ""
	private var userCancelled = false

	private let activityIndicator = UIActivityIndicatorView(style: .medium)
	private let resolvedURLHintLabel = UILabel()

	var initialFeed: String?
	var initialFeedName: String?

	var container: Container?

	override func viewDidLoad() {
        super.viewDidLoad()

		if initialFeed == nil, let urlString = UIPasteboard.general.string {
			if urlString.mayBeURL {
				initialFeed = urlString.normalizedURL
			}
		}

		urlTextField.autocorrectionType = .no
		urlTextField.autocapitalizationType = .none
		urlTextField.text = initialFeed
		urlTextField.delegate = self

		if initialFeed != nil {
			addButton.isEnabled = true
		}

		nameTextField.text = initialFeedName
		nameTextField.delegate = self

		if let defaultContainer = AddFeedDefaultContainer.defaultContainer {
			container = defaultContainer
		} else {
			addButton.isEnabled = false
		}

		updateFolderLabel()
		setUpResolvedURLHintLabel()
		updateResolvedURLHint()

		tableView.register(UINib(nibName: "AddFeedSelectFolderTableViewCell", bundle: nil), forCellReuseIdentifier: "AddFeedSelectFolderTableViewCell")

		NotificationCenter.default.addObserver(self, selector: #selector(textDidChange(_:)), name: UITextField.textDidChangeNotification, object: urlTextField)

		if initialFeed == nil {
			urlTextField.becomeFirstResponder()
		}
	}

	@IBAction func cancel(_ sender: Any) {
		userCancelled = true
		dismiss(animated: true)
	}

	@IBAction func add(_ sender: Any) {

		let urlString = urlTextField.text ?? ""
		let normalizedURLString = urlString.normalizedURL

		guard !normalizedURLString.isEmpty, let url = URL(string: normalizedURLString) else {
			return
		}

		guard let container = container else { return }

		var account: Account?
		if let containerAccount = container as? Account {
			account = containerAccount
		} else if let containerFolder = container as? Folder, let containerAccount = containerFolder.account {
			account = containerAccount
		}

		let userEnteredURLString = normalizedURLString
		let resolvedURL = RSSHubResolver().resolvedURL(for: userEnteredURLString)

		if account!.hasFeed(withURL: (resolvedURL ?? url).absoluteString) {
			presentError(AccountError.createErrorAlreadySubscribed)
 			return
		}

		addButton.isEnabled = false
		addButton.customView = activityIndicator
		addButton.customView?.isHidden = false
		activityIndicator.startAnimating()

		let feedName = (nameTextField.text?.isEmpty ?? true) ? nil : nameTextField.text

		BatchUpdate.shared.start()

		account!.createFeed(url: url.absoluteString, name: feedName, container: container, validateFeed: true) { result in

			BatchUpdate.shared.end()

			switch result {
			case .success(let feed):
				self.dismiss(animated: true)
				NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
			case .failure(let error):
				self.addButton.isEnabled = true
				self.activityIndicator.stopAnimating()
				self.addButton.customView = nil
				let presented = RSSHubError.subscriptionFailure(forUserEnteredURL: userEnteredURLString, underlying: error) ?? error
				self.presentError(presented)
			}

		}

	}

	@objc func textDidChange(_ note: Notification) {
		updateUI()
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row == 2 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "AddFeedSelectFolderTableViewCell", for: indexPath) as? AddFeedSelectFolderTableViewCell
			cell!.detailLabel.text = folderLabel
			return cell!
		} else {
			return super.tableView(tableView, cellForRowAt: indexPath)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.row == 2 {
			let navController = UIStoryboard.add.instantiateViewController(withIdentifier: "AddFeedFolderNavViewController") as! UINavigationController
			navController.modalPresentationStyle = .currentContext
			let folderViewController = navController.topViewController as! AddFeedFolderViewController
			folderViewController.delegate = self
			folderViewController.initialContainer = container
			present(navController, animated: true)
		}
	}

}

// MARK: AddFeedFolderViewControllerDelegate

extension AddFeedViewController: AddFeedFolderViewControllerDelegate {
	func didSelect(container: Container) {
		self.container = container
		updateFolderLabel()
		AddFeedDefaultContainer.saveDefaultContainer(container)
	}
}

// MARK: UITextFieldDelegate

extension AddFeedViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

}

// MARK: Private

private extension AddFeedViewController {

	func updateUI() {
		addButton.isEnabled = (urlTextField.text?.mayBeURL ?? false)
		updateResolvedURLHint()
	}

	private func setUpResolvedURLHintLabel() {
		resolvedURLHintLabel.font = .preferredFont(forTextStyle: .footnote)
		resolvedURLHintLabel.textColor = .secondaryLabel
		resolvedURLHintLabel.numberOfLines = 2
		resolvedURLHintLabel.textAlignment = .center
		resolvedURLHintLabel.adjustsFontSizeToFitWidth = true
		resolvedURLHintLabel.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
		resolvedURLHintLabel.isHidden = true
		tableView.tableFooterView = resolvedURLHintLabel
	}

	/// Shows what a `rsshub://` URL will be expanded to, so a misconfigured
	/// instance is visible before the subscription is attempted.
	private func updateResolvedURLHint() {
		guard let text = urlTextField.text, let resolvedURL = RSSHubResolver().resolvedURL(for: text) else {
			resolvedURLHintLabel.isHidden = true
			resolvedURLHintLabel.text = nil
			resolvedURLHintLabel.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
			tableView.tableFooterView = resolvedURLHintLabel
			return
		}
		let format = NSLocalizedString("Will be resolved to %@", comment: "Add Feed sheet hint showing the expanded URL")
		resolvedURLHintLabel.text = NSString.localizedStringWithFormat(format as NSString, resolvedURL.absoluteString)
		resolvedURLHintLabel.isHidden = false
		resolvedURLHintLabel.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 48)
		tableView.tableFooterView = resolvedURLHintLabel
	}

	func updateFolderLabel() {
		if let containerName = (container as? DisplayNameProvider)?.nameForDisplay {
			if container is Folder {
				folderLabel = "\(container?.account?.nameForDisplay ?? "") / \(containerName)"
			} else {
				folderLabel = containerName
			}
			tableView.reloadData()
		}
	}
}
