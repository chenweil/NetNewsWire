//
//  RSSHubSettingsView.swift
//  NetNewsWire
//

import Foundation
import SwiftUI

struct RSSHubSettingsView: View {

	@State private var baseURLString = ""
	@State private var accessKey = ""
	@State private var testResult: TestResult?
	@State private var isTesting = false
	@FocusState private var focusedField: Field?

	private enum Field {
		case baseURL
		case accessKey
	}

	private enum TestResult {
		case success(String)
		case failure(String)
	}

	private let settings = RSSHubSettings.shared

	var body: some View {
		List {
			Section {
				TextField("https://rsshub.app", text: $baseURLString)
					.textContentType(.URL)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
					.focused($focusedField, equals: .baseURL)
					.onSubmit(saveFields)
			} header: {
				Text("Instance address")
			} footer: {
				Text("NetNewsWire expands rsshub:// URLs into real feed addresses using this instance, so rsshub://telegram/channel/somechannel becomes <instance>/telegram/channel/somechannel. The official demo instance is rate-limited and often refuses non-browser clients, so a self-hosted instance is more reliable.")
			}

			Section {
				SecureField("Only if the instance requires one", text: $accessKey)
					.textContentType(.password)
					.focused($focusedField, equals: .accessKey)
					.onSubmit(saveFields)
			} header: {
				Text("Access key")
			} footer: {
				Text("Sent as the ?key= query parameter on every request. Leave empty if the instance is open.")
			}

			Section {
				Button(isTesting ? "Testing…" : "Test Connection") {
					testConnection()
				}
				.disabled(isTesting)

				if let testResult {
					switch testResult {
					case .success(let message):
						Label(message, systemImage: "checkmark.circle.fill")
							.foregroundStyle(.green)
					case .failure(let message):
						Label(message, systemImage: "exclamationmark.triangle.fill")
							.foregroundStyle(.red)
					}
				}
			}
		}
		.navigationTitle("RSSHub")
		.onAppear {
			baseURLString = settings.baseURLString
			accessKey = settings.accessKey ?? ""
		}
		.onChange(of: focusedField) {
			if focusedField == nil {
				saveFields()
			}
		}
	}

	// MARK: - Actions

	private func saveFields() {
		testResult = nil
		if baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			settings.resetBaseURL()
			baseURLString = settings.baseURLString
		} else if settings.setBaseURLString(baseURLString) == nil {
			testResult = .failure(NSLocalizedString("The instance address isn’t a valid http or https URL.", comment: "RSSHub settings"))
			return
		}

		do {
			try settings.setAccessKey(accessKey)
		} catch {
			testResult = .failure(NSLocalizedString("Couldn’t save the access key.", comment: "RSSHub settings"))
		}
	}

	private func testConnection() {
		saveFields()
		if case .failure = testResult { return }

		isTesting = true
		let healthURL = settings.healthCheckURL

		Task {
			let result: TestResult
			do {
				let (_, response) = try await URLSession.shared.data(from: healthURL)
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
				switch statusCode {
				case 200..<300:
					result = .success(NSLocalizedString("Instance is reachable.", comment: "RSSHub settings"))
				case 403:
					result = .failure(NSLocalizedString("Instance rejected the request. Public instances often refuse non-browser clients.", comment: "RSSHub settings"))
				case 404:
					result = .failure(NSLocalizedString("No health endpoint — the instance may not be an RSSHub server.", comment: "RSSHub settings"))
				default:
					result = .failure(NSLocalizedString("Unexpected response: HTTP \(statusCode).", comment: "RSSHub settings"))
				}
			} catch {
				result = .failure(NSLocalizedString("Couldn’t reach the instance.", comment: "RSSHub settings"))
			}

			await MainActor.run {
				isTesting = false
				testResult = result
			}
		}
	}
}