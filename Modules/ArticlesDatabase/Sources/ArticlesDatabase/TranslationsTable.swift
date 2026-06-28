//
//  TranslationsTable.swift
//  ArticlesDatabase
//
//  Persistence for `Translation` records. The `translations` table is keyed
//  by `(articleID, targetLanguage, bodySource)` — switching the target
//  language in preferences, or toggling the article extractor, is a natural
//  cache miss, not an explicit invalidation.
//

import Foundation
import RSDatabase
import RSDatabaseObjC

// CREATE TABLE if not EXISTS translations (
//     articleID TEXT NOT NULL,
//     targetLanguage TEXT NOT NULL,
//     bodySource TEXT NOT NULL,
//     title TEXT NOT NULL,
//     translationBody TEXT NOT NULL,
//     engine TEXT NOT NULL,
//     translatedAt INTEGER NOT NULL,
//     PRIMARY KEY (articleID, targetLanguage, bodySource)
// );

final class TranslationsTable: DatabaseTable, Sendable {

	let name = DatabaseTableName.translations
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	// MARK: - Fetching

	func fetchTranslation(
		articleID: String,
		targetLanguage: String,
		bodySource: ArticleTranslation.BodySource
	) -> ArticleTranslation? {
		nonisolated(unsafe) var result: ArticleTranslation?

		queue.runInDatabaseSync { database in
			result = self.fetchTranslation(
				articleID: articleID,
				targetLanguage: targetLanguage,
				bodySource: bodySource,
				database: database
			)
		}

		return result
	}

	func fetchTranslation(
		articleID: String,
		targetLanguage: String,
		bodySource: ArticleTranslation.BodySource,
		database: FMDatabase
	) -> ArticleTranslation? {
		let sql = """
			select title, translationBody, engine, translatedAt
			from translations
			where articleID = ? and targetLanguage = ? and bodySource = ?
			limit 1;
		"""
		let parameters: [Any] = [articleID, targetLanguage, bodySource.rawValue]
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
			return nil
		}
		defer { resultSet.close() }

		guard resultSet.next() else { return nil }

		return Self.translation(
			articleID: articleID,
			targetLanguage: targetLanguage,
			bodySource: bodySource,
			row: resultSet
		)
	}

	// MARK: - Saving

	/// Insert or replace a translation. Idempotent on
	/// `(articleID, targetLanguage, bodySource)`.
	func upsertTranslation(_ translation: ArticleTranslation, database: FMDatabase) {
		let dictionary: DatabaseDictionary = [
			DatabaseKey.articleID: translation.articleID,
			DatabaseKey.targetLanguage: translation.targetLanguage,
			DatabaseKey.bodySource: translation.bodySource.rawValue,
			DatabaseKey.title: translation.title,
			DatabaseKey.translationBody: translation.body,
			DatabaseKey.engine: translation.engine.rawValue,
			DatabaseKey.translatedAt: translation.translatedAt.timeIntervalSince1970,
		]
		insertRow(dictionary, insertType: .orReplace, in: database)
	}

	func upsertTranslation(_ translation: ArticleTranslation) {
		queue.runInTransaction { database in
			self.upsertTranslation(translation, database: database)
		}
	}

	// MARK: - Deleting

	/// Delete one translation row. Used by retry flows.
	func deleteTranslation(
		articleID: String,
		targetLanguage: String,
		bodySource: ArticleTranslation.BodySource,
		database: FMDatabase
	) {
		let sql = """
			delete from translations
			where articleID = ? and targetLanguage = ? and bodySource = ?;
		"""
		let parameters: [Any] = [articleID, targetLanguage, bodySource.rawValue]
		database.executeUpdate(sql, withArgumentsIn: parameters)
	}

	// MARK: - Helpers

	private static func translation(
		articleID: String,
		targetLanguage: String,
		bodySource: ArticleTranslation.BodySource,
		row: FMResultSet
	) -> ArticleTranslation? {
		guard
			let title = row.swiftString(forColumn: DatabaseKey.title),
			let body = row.swiftString(forColumn: DatabaseKey.translationBody),
			let engineRaw = row.swiftString(forColumn: DatabaseKey.engine),
			let engine = ArticleTranslation.Engine(rawValue: engineRaw)
		else {
			return nil
		}

		let translatedAt = Date(timeIntervalSince1970: row.double(forColumn: DatabaseKey.translatedAt))

		return ArticleTranslation(
			articleID: articleID,
			targetLanguage: targetLanguage,
			bodySource: bodySource,
			title: title,
			body: body,
			engine: engine,
			translatedAt: translatedAt
		)
	}
}
