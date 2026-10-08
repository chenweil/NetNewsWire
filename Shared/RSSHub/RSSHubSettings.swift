//
//  RSSHubSettings.swift
//  NetNewsWire
//

import Foundation
import RSCore
import Secrets

/// Settings for resolving `rsshub://` feed URLs.
///
/// The instance address is a plain preference stored in `UserDefaults`. The
/// access key is a secret and lives in the keychain, matching how
/// `TranslationSettings` treats the OpenAI API key.
public final class RSSHubSettings: @unchecked Sendable {

	public static let shared = RSSHubSettings()

	/// Namespace used for the keychain entry. Must be unique per secret.
	public static let credentialsServer = "rsshub"
	public static let credentialsUsername = "access-key"

	/// Used when the user hasn’t configured an instance. The official demo
	/// instance is rate-limited and often rejects non-browser clients, so this
	/// is only a fallback that works if it works.
	public static let defaultBaseURLString = "https://rsshub.app"

	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	private enum Key {
		static let baseURL = "rsshub.baseURL"
	}

	// MARK: - Instance address

	/// The stored instance address, normalized. Falls back to
	/// ``defaultBaseURLString`` when unset or unparseable.
	public var baseURLString: String {
		guard
			let raw = defaults.string(forKey: Key.baseURL)?.trimmingWhitespace,
			!raw.isEmpty
		else {
			return Self.defaultBaseURLString
		}
		return Self.normalizeBaseURLString(raw) ?? Self.defaultBaseURLString
	}

	public var baseURL: URL? {
		let normalized = baseURLString
		guard !normalized.isEmpty else { return nil }
		return URL(string: normalized)
	}

	/// Stores the instance address. Returns the normalized value that was
	/// stored, or `nil` if the input isn’t a usable http(s) address.
	@discardableResult
	public func setBaseURLString(_ raw: String) -> String? {
		let trimmed = raw.trimmingWhitespace
		guard !trimmed.isEmpty else {
			resetBaseURL()
			return nil
		}
		guard let normalized = Self.normalizeBaseURLString(trimmed) else {
			return nil
		}
		defaults.set(normalized, forKey: Key.baseURL)
		return normalized
	}

	/// Restores the default instance address.
	public func resetBaseURL() {
		defaults.removeObject(forKey: Key.baseURL)
	}

	/// Adds a scheme when one is missing and drops the trailing slash, so the
	/// value can be concatenated with a route path. A subpath prefix such as
	/// `https://host/rsshub` is preserved. A non-http scheme is rejected rather
	/// than being treated as a hostname.
	public static func normalizeBaseURLString(_ raw: String) -> String? {
		var candidate = raw.trimmingWhitespace
		guard !candidate.isEmpty else { return nil }

		if candidate.contains("://") {
			guard
				let scheme = URL(string: candidate)?.scheme?.lowercased(),
				scheme == "http" || scheme == "https"
			else {
				return nil
			}
		} else {
			candidate = "https://\(candidate)"
		}

		while candidate.hasSuffix("/") {
			candidate.removeLast()
		}

		guard
			let url = URL(string: candidate),
			url.scheme?.lowercased().hasPrefix("http") == true,
			let host = url.host,
			!host.isEmpty
		else {
			return nil
		}

		return candidate
	}

	// MARK: - Access key

	/// The configured access key, or `nil` when unset or unreadable.
	public var accessKey: String? {
		guard
			let credentials = try? CredentialsManager.retrieveCredentials(
				type: .rsshubAccessKey,
				server: Self.credentialsServer,
				username: Self.credentialsUsername
			)
		else {
			return nil
		}
		let key = credentials.secret.trimmingWhitespace
		return key.isEmpty ? nil : key
	}

	/// Stores the access key. An empty string removes it.
	public func setAccessKey(_ raw: String) throws {
		let key = raw.trimmingWhitespace
		guard !key.isEmpty else {
			try CredentialsManager.removeCredentials(
				type: .rsshubAccessKey,
				server: Self.credentialsServer,
				username: Self.credentialsUsername
			)
			return
		}
		try CredentialsManager.storeCredentials(
			Credentials(type: .rsshubAccessKey, username: Self.credentialsUsername, secret: key),
			server: Self.credentialsServer
		)
	}

	public var hasAccessKey: Bool {
		accessKey != nil
	}

	// MARK: - Health check

	/// Builds `<instance>/healthz`. RSSHub protects `/healthz` with the same
	/// `?key=` query it uses for routes.
	public var healthCheckURL: URL {
		let base = baseURLString
		var components = URLComponents(string: "\(base)/healthz")
		if let accessKey {
			components?.queryItems = [URLQueryItem(name: "key", value: accessKey)]
		}
		return components?.url ?? URL(string: "\(base)/healthz")!
	}
}