//
//  AboutWindowController.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 26/06/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import AppKit

final class AboutWindowController: NSWindowController {
	@IBOutlet var appIconImageView: NSImageView!
	@IBOutlet var appTitleLabel: NSTextField!
	@IBOutlet var versionLabel: NSTextField!
	@IBOutlet var copyrightLabel: LinksTextView!
	@IBOutlet var websiteLabel: LinkLabel!
	@IBOutlet var creditsTextView: LinksTextView!

	override func windowDidLoad() {
		super.windowDidLoad()
		configureWindow()
		updateUI()
	}

	/// A short, human-facing form of a URL, for showing in the About window.
	nonisolated static func displayText(for url: URL) -> String {
		var text = url.absoluteString
		for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
			text.removeFirst(scheme.count)
			break
		}
		if text.hasPrefix("www.") {
			text.removeFirst("www.".count)
		}
		return text
	}
}

private extension AboutWindowController {

	/// The person responsible for this build of the app, and where to find them.
	struct VersionAuthor {
		let name: String
		let url: URL
	}

	/// The website of the project this app is based on.
	static let upstreamURL = URL(string: "https://netnewswire.com/")

	/// The author of this version, as configured in the app bundle.
	///
	/// A build that does not name an author falls back to the upstream project.
	static var versionAuthor: VersionAuthor? {
		guard
			let name = Bundle.main.infoDictionary?["NNWVersionAuthor"] as? String,
			!name.isEmpty,
			let urlString = Bundle.main.infoDictionary?["NNWVersionAuthorURL"] as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}
		return VersionAuthor(name: name, url: url)
	}

	func configureWindow() {
		window?.isOpaque = false
		window?.backgroundColor = .clear
		window?.titlebarAppearsTransparent = true
		window?.titleVisibility = .hidden
		window?.styleMask.insert(.fullSizeContentView)
		if #available(macOS 26.0, *) {
			if let contentView = window?.contentView {
				let visualEffectView = NSGlassEffectView(frame: contentView.bounds)
				visualEffectView.tintColor = .clear
				visualEffectView.autoresizingMask = [.width, .height]
				contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
			}
		} else {
			if let contentView = window?.contentView {
				let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
				visualEffectView.blendingMode = .behindWindow
				visualEffectView.material = .underWindowBackground
				visualEffectView.state = .active
				visualEffectView.autoresizingMask = [.width, .height]
				contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
			}
		}
	}

	func updateUI() {
		// App Icon
		appIconImageView.image = NSApp.applicationIconImage

		// Version
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
		let versionString = "Version \(version) (Build \(build))"
		versionLabel.stringValue = versionString

		// Copyright
		let copyrightText = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
		let copyrightAttributedString = NSMutableAttributedString(string: copyrightText)
		let copyrightFullRange = NSRange(location: 0, length: copyrightAttributedString.length)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .center
		copyrightAttributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: copyrightFullRange)
		copyrightAttributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: copyrightFullRange)
		copyrightAttributedString.addAttribute(.font, value: NSFont.preferredFont(forTextStyle: .subheadline), range: copyrightFullRange)

		// The upstream author of the project this app is based on.
		if let nameRange = copyrightText.range(of: "Brent Simmons"),
		   let url = URL(string: "https://inessential.com/") {
			let nsRange = NSRange(nameRange, in: copyrightText)
			copyrightAttributedString.addAttribute(.link, value: url, range: nsRange)
		}

		// The author of this version. Their name is the last thing in the
		// copyright line, so look for it from the back.
		if let author = Self.versionAuthor,
		   let nameRange = copyrightText.range(of: author.name, options: .backwards) {
			let nsRange = NSRange(nameRange, in: copyrightText)
			copyrightAttributedString.addAttribute(.link, value: author.url, range: nsRange)
		}

		copyrightLabel.textStorage?.setAttributedString(copyrightAttributedString)

		// Credits
		if let creditsURL = Bundle.main.url(forResource: "Credits", withExtension: "rtf"),
		   let creditsData = try? Data(contentsOf: creditsURL),
		   let attributedString = try? NSAttributedString(data: creditsData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
			creditsTextView.textStorage?.setAttributedString(attributedString)
		} else {
			creditsTextView.string = "Credits not available."
		}

		let fullRange = NSRange(location: 0, length: creditsTextView.string.utf16.count)
		let leadingParagraphStyle = NSMutableParagraphStyle()
		leadingParagraphStyle.alignment = .left
		creditsTextView.textStorage?.addAttribute(.paragraphStyle, value: leadingParagraphStyle, range: fullRange)

		// URL
		if let websiteURL = Self.versionAuthor?.url ?? Self.upstreamURL {
			let attributedString = NSMutableAttributedString(string: Self.displayText(for: websiteURL))
			attributedString.addAttribute(.link, value: websiteURL, range: NSRange(location: 0, length: attributedString.length))
			attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: NSRange(location: 0, length: attributedString.length))
			attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributedString.length))
			websiteLabel.attributedStringValue = attributedString
		}
	}
}
