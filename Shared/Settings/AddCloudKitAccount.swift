//
//  AddCloudKitAccount.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/22/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import RSCore

enum AddCloudKitAccountError: LocalizedError, RecoverableError, Sendable {
	case iCloudDriveMissing
	case cloudKitUnavailable

	var errorDescription: String? {
		NSLocalizedString("Can’t Add iCloud Account", comment: "CloudKit account setup failure description.")
	}

	var recoverySuggestion: String? {
		if case .cloudKitUnavailable = self {
			return NSLocalizedString("This build of NetNewsWire is not signed with iCloud support.", comment: "CloudKit account setup recovery suggestion — entitlement unavailable.")
		}

		#if os(macOS)
		return NSLocalizedString("Open System Settings to configure iCloud and enable iCloud Drive.", comment: "CloudKit account setup recovery suggestion")
		#else
		return NSLocalizedString("Open Settings to configure iCloud and enable iCloud Drive.", comment: "CloudKit account setup recovery suggestion")
		#endif
	}

	var recoveryOptions: [String] {
		if case .cloudKitUnavailable = self {
			return [NSLocalizedString("OK", comment: "OK button")]
		}

		#if os(macOS)
		return [NSLocalizedString("Open System Settings", comment: "Open System Settings button"), NSLocalizedString("Cancel", comment: "Cancel button")]
		#else
		return [NSLocalizedString("Open Settings", comment: "Open Settings button"), NSLocalizedString("Cancel", comment: "Cancel button")]
		#endif
	}

	func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool {
		if case .cloudKitUnavailable = self {
			return false
		}

		guard recoveryOptionIndex == 0 else {
			return false
		}

		Task { @MainActor in
			AddCloudKitAccountUtilities.openiCloudSettings()
		}

		return true
	}
}

struct AddCloudKitAccountUtilities {
	static var isiCloudDriveEnabled: Bool {
		Platform.deviceHasiCloudAccount
	}

	static var isCloudKitAvailable: Bool {
		Platform.appHasCloudKitEntitlement
	}

	@MainActor static func openiCloudSettings() {
#if os(macOS)
		if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
			NSWorkspace.shared.open(url)
		}
#else
		if let url = URL(string: "App-prefs:APPLE_ACCOUNT") {
			UIApplication.shared.open(url)
		}
#endif
	}
}
