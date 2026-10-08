//
//  Downloader.swift
//  RSWeb
//
//  Created by Brent Simmons on 8/27/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os
import RSCore

public typealias DownloadCallback = @MainActor (DownloadResponse, Error?) -> Swift.Void

/// Simple downloader, for a one-shot download like an image
/// or a web page. For a download-feeds session, see DownloadSession.
/// Caches response for a short time for GET requests. May return cached response.
@MainActor public final class Downloader: NSObject {
	public static let shared = Downloader()
	private let urlSession: URLSession
	private var callbacks = [String: [(callback: DownloadCallback, fromCache: Bool)]]()
	fileprivate var taskContexts = [String: FeedRequestContext]()
	private let cache = DownloadCache.shared

	nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Downloader")

	init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
		sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
		sessionConfiguration.httpShouldSetCookies = false
		sessionConfiguration.httpCookieAcceptPolicy = .never
		sessionConfiguration.httpMaximumConnectionsPerHost = 1
		sessionConfiguration.httpCookieStorage = nil

		if let userAgentHeaders = UserAgent.headers() {
			sessionConfiguration.httpAdditionalHeaders = userAgentHeaders
		}

		// A delegate proxy avoids URLSession retaining this downloader forever.
		let redirectDelegate = DownloaderRedirectDelegate()
		urlSession = URLSession(configuration: sessionConfiguration, delegate: redirectDelegate, delegateQueue: .main)
		super.init()
		redirectDelegate.downloader = self
	}

	deinit {
		urlSession.invalidateAndCancel()
	}

	public func download(_ url: URL) async throws -> DownloadResponse {
		try await withCheckedThrowingContinuation { continuation in
			download(url) { downloadResponse, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: downloadResponse)
				}
			}
		}
	}

	public func download(_ url: URL, _ callback: @escaping DownloadCallback) {
		assert(Thread.isMainThread)
		download(URLRequest(url: url), callback)
	}

	public func download(_ urlRequest: URLRequest, _ callback: @escaping DownloadCallback) {
		assert(Thread.isMainThread)

		guard let url = urlRequest.url else {
			Self.logger.fault("Downloader: skipping download for URLRequest without a URL")
			return
		}

		guard url.isHTTPOrHTTPSURL() else {
			Self.logger.debug("Downloader: skipping download for non-http/https URL: \(url)")
			callback(DownloadResponse(data: nil, response: nil, returnedFromCache: false), nil)
			return
		}

		let isCacheableRequest = urlRequest.httpMethod == HTTPMethod.get
		let context = FeedRequestAuthorization.context(for: url)
		let cacheKey = url.absoluteString + (context.map { "#authorization=" + $0.cacheIdentifier } ?? "")

		// Return cached record if available.
		if isCacheableRequest {
			if let cachedRecord = cache[cacheKey] {
				Self.logger.debug("Downloader: returning cached record for \(url)")
				callback(DownloadResponse(data: cachedRecord.data, response: cachedRecord.response, returnedFromCache: true), nil)
				return
			}
		}

		// Add callback. If there is already a download in progress for this URL, return early.
		if callbacks[cacheKey] == nil {
			Self.logger.debug("Downloader: downloading \(url)")
			callbacks[cacheKey] = [(callback, false)]
		} else {
			// A download is already in progress for this URL. Don’t start a separate download.
			// Add the callback to the callbacks array for this URL. This caller is coalesced
			// onto the in-progress download, so it makes no network request of its own.
			Self.logger.debug("Downloader: download in progress for \(url) — adding callback")
			callbacks[cacheKey]?.append((callback, true))
			return
		}

		var urlRequestToUse = urlRequest
		urlRequestToUse.addSpecialCaseUserAgentIfNeeded()
		urlRequestToUse = context?.prepare(urlRequestToUse) ?? urlRequestToUse

		let task = urlSession.dataTask(with: urlRequestToUse) { (data, response, error) in

			if isCacheableRequest {
				Self.logger.debug("Downloader: caching response for \(url)")
				self.cache.add(cacheKey, data: data, response: response)
			}

			Task { @MainActor in
				self.taskContexts[cacheKey] = nil
				self.callAndReleaseCallbacks(cacheKey, url: url, data, response, error)
			}
		}
		task.taskDescription = cacheKey
		taskContexts[cacheKey] = context
		task.resume()
	}
}

@MainActor private final class DownloaderRedirectDelegate: NSObject, @preconcurrency URLSessionTaskDelegate {
	weak var downloader: Downloader?

	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		var redirectedRequest = request
		if let key = task.taskDescription, let context = downloader?.taskContexts[key] {
			redirectedRequest = context.prepareRedirect(request)
		}
		redirectedRequest.addSpecialCaseUserAgentIfNeeded()
		completionHandler(redirectedRequest)
	}
}

private extension Downloader {

	func callAndReleaseCallbacks(_ cacheKey: String, url: URL, _ data: Data? = nil, _ response: URLResponse? = nil, _ error: Error? = nil) {
		assert(Thread.isMainThread)

		defer {
			callbacks[cacheKey] = nil
		}

		guard let callbacksForURL = callbacks[cacheKey] else {
			assertionFailure("Downloader: downloaded URL \(url) but no callbacks found")
			Self.logger.fault("Downloader: downloaded URL \(url) but no callbacks found")
			return
		}

		let count = callbacksForURL.count
		if count == 1 {
			Self.logger.debug("Downloader: calling 1 callback for URL \(url)")
		} else {
			Self.logger.debug("Downloader: calling \(count) callbacks for URL \(url)")
		}

		for entry in callbacksForURL {
			let downloadResponse = DownloadResponse(data: data, response: response, returnedFromCache: entry.fromCache)
			entry.callback(downloadResponse, error)
		}
	}
}
