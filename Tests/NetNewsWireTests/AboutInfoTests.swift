//
//  AboutInfoTests.swift
//  NetNewsWireTests
//
//  Tests for the information the About window shows.
//

import AppKit
import CoreText
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

    @Test("The copyright line fits the label that holds it")
    func copyrightFitsItsLabel() throws {
        let copyright = try #require(Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String)
        let labelSize = try Self.copyrightLabelSize()

        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        let attributed = NSAttributedString(string: copyright, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: labelSize.width, height: .greatestFiniteMagnitude),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributed.length), path, nil)
        let lineCount = CFArrayGetCount(CTFrameGetLines(frame))
        let lineHeight = font.ascender - font.descender + font.leading

        // The label does not grow, so text that needs more room than the
        // label has is silently cut off.
        #expect(Double(lineCount) * lineHeight <= labelSize.height)
    }

    /// The size of the copyright label in the About window, read from the nib.
    ///
    /// The About window is laid out by hand, so the copyright string has to
    /// fit its label exactly. Reading the nib keeps this check tied to the
    /// real layout instead of a copy of it.
    private static func copyrightLabelSize() throws -> CGSize {
        let nibURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Mac/About/AboutWindowController.xib")
        let nib = try String(contentsOf: nibURL, encoding: .utf8)

        let identifier = try #require(
            text(in: nib, after: #"<outlet property="copyrightLabel" destination=""#, upTo: "\""),
            "The nib does not connect the copyright label"
        )

        guard let elementStart = nib.range(of: #"id=""# + identifier + #"""#) else {
            throw LabelSizeError.missingElement
        }
        let element = String(nib[elementStart.lowerBound...])

        let width = try #require(
            text(in: element, after: #"<size key="maxSize" width=""#, upTo: "\""),
            "The nib does not give the copyright label a fixed width"
        )
        let height = try #require(
            text(in: element, after: #"<size key="maxSize" width="\#(width)" height=""#, upTo: "\""),
            "The nib does not give the copyright label a fixed height"
        )

        return CGSize(
            width: try #require(Double(width)),
            height: try #require(Double(height))
        )
    }

    /// The text between the end of `marker` and the next `terminator`.
    private static func text(in string: String, after marker: String, upTo terminator: String) -> String? {
        guard let start = string.range(of: marker)?.upperBound else { return nil }
        guard let end = string.range(of: terminator, range: start..<string.endIndex)?.lowerBound else { return nil }
        return String(string[start..<end])
    }

    private enum LabelSizeError: Error {
        case missingElement
    }
}
