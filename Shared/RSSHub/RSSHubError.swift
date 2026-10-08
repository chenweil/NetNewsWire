//
//  RSSHubError.swift
//  NetNewsWire
//

import Foundation
import RSCore

public enum RSSHubError: Error, LocalizedError, Equatable {

	case invalidInstance
	case invalidRoute
	case browserVerificationRequired(statusCode: Int?)

	/// The instance rejected the request (HTTP 401/403).
	case accessDenied(statusCode: Int?)

	/// The route doesn’t exist on the instance (HTTP 404).
	case routeNotFound(statusCode: Int?)

	/// The instance is limiting the request rate (HTTP 429).
	case rateLimited(statusCode: Int?)

	/// The instance itself failed (HTTP 5xx).
	case serverError(statusCode: Int?)

	/// The instance didn’t answer, or answered with something else.
	/// Includes connection failures and network timeouts.
	case unreachable(statusCode: Int?)

	public var errorDescription: String? {
		switch self {
		case .invalidInstance:
			return NSLocalizedString("The RSSHub instance address isn’t a valid URL.", comment: "RSSHub error")
		case .invalidRoute:
			return NSLocalizedString("The RSSHub URL doesn’t contain a route to request.", comment: "RSSHub error")
		case .browserVerificationRequired(let statusCode):
			return NSLocalizedString("The RSSHub instance requires browser verification.", comment: "RSSHub error") + Self.statusSuffix(statusCode: statusCode)
		case .accessDenied(let statusCode):
			return NSLocalizedString("The RSSHub instance refused access.", comment: "RSSHub error") + Self.statusSuffix(statusCode: statusCode)
		case .rateLimited(let statusCode):
			return NSLocalizedString("The RSSHub instance is limiting the request rate.", comment: "RSSHub error") + Self.statusSuffix(statusCode: statusCode)
		case .serverError(let statusCode):
			return NSLocalizedString("The RSSHub instance hit an internal error.", comment: "RSSHub error") + Self.statusSuffix(statusCode: statusCode)
		case .unreachable(let statusCode):
			return Self.unreachableDescription(statusCode: statusCode)
		case .routeNotFound(let statusCode):
			return NSLocalizedString("The RSSHub route doesn’t exist on the configured instance.", comment: "RSSHub error") + Self.statusSuffix(statusCode: statusCode)
		}
	}

	public var recoverySuggestion: String? {
		switch self {
		case .invalidInstance:
			return NSLocalizedString("Check the RSSHub instance address in Preferences.", comment: "RSSHub error suggestion")
		case .invalidRoute:
			return NSLocalizedString("RSSHub URLs look like rsshub://namespace/route, for example rsshub://telegram/channel/somechannel.", comment: "RSSHub error suggestion")
		case .browserVerificationRequired:
			return NSLocalizedString("Open RSSHub preferences and verify the feed in a browser, then try again.", comment: "RSSHub error suggestion")
		case .accessDenied:
			return NSLocalizedString("The instance may require an access key or may not serve this channel publicly.", comment: "RSSHub error suggestion")
		case .rateLimited:
			return NSLocalizedString("Wait a little while and try again. Public instances are often rate-limited — a self-hosted instance is more reliable.", comment: "RSSHub error suggestion")
		case .serverError:
			return NSLocalizedString("The instance itself is failing. Try again later, or switch to another instance in Preferences.", comment: "RSSHub error suggestion")
		case .unreachable:
			return NSLocalizedString("The RSSHub instance didn’t respond. Public instances are often overloaded or rate-limited — a self-hosted instance is more reliable.", comment: "RSSHub error suggestion")
		case .routeNotFound:
			return NSLocalizedString("Double-check the route, and whether the channel is public. Note that restricted channels can’t be subscribed to.", comment: "RSSHub error suggestion")
		}
	}

	private static func unreachableDescription(statusCode: Int?) -> String {
		let format = NSLocalizedString("Couldn’t reach the RSSHub instance at %@.", comment: "RSSHub error")
		return NSString.localizedStringWithFormat(format as NSString, RSSHubSettings.shared.baseURLString) as String + Self.statusSuffix(statusCode: statusCode)
	}

	private static func statusSuffix(statusCode: Int?) -> String {
		guard let statusCode else { return "" }
		return " (\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized))"
	}
}

public extension RSSHubError {

	/// Whether the URL points at the configured RSSHub instance.
	///
	/// RSSHub URLs are stored expanded, so the app has no other way to know a
	/// feed came from `rsshub://`. Matching on the instance host is the only
	/// signal available at subscription time.
	static func ownsURL(_ url: URL?, settings: RSSHubSettings = .shared) -> Bool {
		guard
			let url,
			let host = url.host,
			let instanceHost = settings.baseURL?.host
		else {
			return false
		}
		return host == instanceHost
	}

	/// Returns an RSSHub-specific error when the failed URL belongs to the
	/// configured instance, and `nil` otherwise.
	static func subscriptionFailure(forURL url: URL?, settings: RSSHubSettings = .shared, underlying error: any Error) -> (any Error)? {
		guard ownsURL(url, settings: settings) else { return nil }
		return failure(for: error)
	}

	/// Classifies a retrieval failure. Only retrieval failures are converted;
	/// business errors (already subscribed, account errors, …) return `nil` so
	/// call sites keep handling them with their own logic.
	private static func failure(for error: any Error) -> (any Error)? {
		guard let retrievalFailure = error as? FeedRetrievalFailure else {
			return nil
		}

		let statusCode = retrievalFailure.httpStatusCode
		if retrievalFailure.requiresBrowserVerification {
			return RSSHubError.browserVerificationRequired(statusCode: statusCode)
		}
		switch statusCode ?? 0 {
		case 401, 403:
			return RSSHubError.accessDenied(statusCode: retrievalFailure.httpStatusCode)
		case 404:
			return RSSHubError.routeNotFound(statusCode: retrievalFailure.httpStatusCode)
		case 429:
			return RSSHubError.rateLimited(statusCode: retrievalFailure.httpStatusCode)
		case 500...599:
			return RSSHubError.serverError(statusCode: retrievalFailure.httpStatusCode)
		default:
			// Includes `nil`: connection failures and network timeouts.
			return RSSHubError.unreachable(statusCode: retrievalFailure.httpStatusCode)
		}
	}

	/// Convenience for call sites that still hold the URL the user typed, which
	/// may be an unexpanded `rsshub://` URL.
	static func subscriptionFailure(forUserEnteredURL urlString: String, settings: RSSHubSettings = .shared, underlying error: any Error) -> (any Error)? {
		guard
			let resolvedURL = RSSHubResolver(settings: settings).resolvedURL(for: urlString)
		else {
			return nil
		}
		return subscriptionFailure(forURL: resolvedURL, settings: settings, underlying: error)
	}
}
