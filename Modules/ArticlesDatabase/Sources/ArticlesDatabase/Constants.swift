//
//  Keys.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/3/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation

// MARK: - Database structure

struct DatabaseTableName {
	static let articles = "articles"
	static let statuses = "statuses"
	static let translations = "translations"
}

struct DatabaseKey {
	// Shared
	static let articleID = "articleID"
	static let url = "url"
	static let title = "title"

	// Article
	static let feedID = "feedID"
	static let uniqueID = "uniqueID"
	static let contentHTML = "contentHTML"
	static let contentText = "contentText"
	static let markdown = "markdown"
	static let externalURL = "externalURL"
	static let summary = "summary"
	static let imageURL = "imageURL"
	static let datePublished = "datePublished"
	static let dateModified = "dateModified"
	static let authors = "authors"
	static let searchRowID = "searchRowID"

	// ArticleStatus
	static let read = "read"
	static let starred = "starred"
	static let dateArrived = "dateArrived"

	// Author
	static let authorID = "authorID"
	static let name = "name"
	static let avatarURL = "avatarURL"
	static let emailAddress = "emailAddress"

	// Search
	static let body = "body"
	static let rowID = "rowid"

	// Translation
	static let targetLanguage = "targetLanguage"
	static let bodySource = "bodySource"
	static let engine = "engine"
	static let translatedAt = "translatedAt"
	static let translationBody = "translationBody"
}
