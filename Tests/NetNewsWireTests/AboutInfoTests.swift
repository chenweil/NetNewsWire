//
//  AboutInfoTests.swift
//  NetNewsWireTests
//
//  Tests for the information the About window shows.
//

import Foundation
import Testing
@testable import NetNewsWire

@Suite("About information")
struct AboutInfoTests {

    @Test("The build names the author of this version")
    func buildNamesItsAuthor() throws {
        let name = try #require(
            Bundle.main.infoDictionary?["NNWVersionAuthor"] as? String,
            "The app bundle does not name the author of this version"
        )
        #expect(!name.isEmpty)
    }

    @Test("The author has a web address that the About window can link to")
    func authorHasAWebAddress() throws {
        let urlString = try #require(
            Bundle.main.infoDictionary?["NNWVersionAuthorURL"] as? String,
            "The app bundle does not point at the author's web address"
        )
        let url = try #require(URL(string: urlString))
        #expect(url.scheme == "https")
        #expect(url.host?.isEmpty == false)
    }

    @Test("The copyright line names the author of this version")
    func copyrightNamesTheAuthor() throws {
        let name = try #require(Bundle.main.infoDictionary?["NNWVersionAuthor"] as? String)
        let copyright = try #require(Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String)
        #expect(copyright.contains(name))
    }

    @Test("The credits list the author of this version with a link")
    func creditsListTheAuthor() throws {
        let urlString = try #require(Bundle.main.infoDictionary?["NNWVersionAuthorURL"] as? String)
        let creditsURL = try #require(
            Bundle.main.url(forResource: "Credits", withExtension: "rtf"),
            "The credits file is missing from the app bundle"
        )
        let credits = try String(contentsOf: creditsURL, encoding: .utf8)
        #expect(credits.contains(urlString))
    }

    @Test("A web address is shown without its scheme")
    func webAddressIsShownWithoutScheme() throws {
        let url = try #require(URL(string: "https://github.com/chenweil/NetNewsWire"))
        #expect(AboutWindowController.displayText(for: url) == "github.com/chenweil/NetNewsWire")

        let wwwURL = try #require(URL(string: "https://www.example.com/"))
        #expect(AboutWindowController.displayText(for: wwwURL) == "example.com/")
    }
}
