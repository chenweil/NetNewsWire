//
//  URLResponse+RSWeb.swift
//  RSWeb
//
//  Created by Brent Simmons on 8/14/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation

nonisolated public extension URLResponse {
	var requiresBrowserVerification: Bool {
		(self as? HTTPURLResponse)?.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
	}

	var statusIsOK: Bool {
		return forcedStatusCode >= 200 && forcedStatusCode <= 299
	}

	var forcedStatusCode: Int {

		// Return actual statusCode or 0 if there isn’t one.

		if let response = self as? HTTPURLResponse {
			return response.statusCode
		}
		return 0
	}

	/// The status code, or `nil` when no HTTP response was received at all.
	var statusCodeIfReceived: Int? {
		guard let response = self as? HTTPURLResponse else { return nil }
		return response.statusCode
	}
}

nonisolated public extension HTTPURLResponse {

	func valueForHTTPHeaderField(_ headerField: String) -> String? {

		// Case-insensitive. HTTP headers may not be in the case you expect.

		let lowerHeaderField = headerField.lowercased()

		for (key, value) in allHeaderFields {

			if lowerHeaderField == (key as? String)?.lowercased() {
				return value as? String
			}
		}

		return nil
	}
}
