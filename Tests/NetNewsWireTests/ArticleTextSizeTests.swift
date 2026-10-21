//
//  ArticleTextSizeTests.swift
//  NetNewsWireTests
//
//  Tests for the article text size classes.
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite("Article text size")
struct ArticleTextSizeTests {

    @Test("Every text size has a rule in the theme stylesheet")
    func textSizeClassesExistInTheme() throws {
        let path = try #require(
            Bundle.main.path(forResource: "stylesheet", ofType: "css"),
            "The theme stylesheet is missing from the app bundle"
        )
        let css = try String(contentsOfFile: path, encoding: .utf8)

        for size in ArticleTextSize.allCases {
            let cssClass = size.cssClass
            #expect(css.contains(".\(cssClass) {"), "The theme stylesheet has no rule for .\(cssClass)")
        }
    }

    @Test("Text size classes are unique")
    func textSizeClassesAreUnique() {
        let classes = ArticleTextSize.allCases.map(\.cssClass)
        #expect(Set(classes).count == classes.count)
    }
}
