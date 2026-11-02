import Foundation
import Testing
@testable import FMPreview

@Suite struct SyntaxTests {
    /// The substrings tagged with `kind`.
    func spans(_ text: String, _ lang: Language, _ kind: SyntaxKind) -> [String] {
        let u = Array(text.utf16)
        return SyntaxHighlighter.tokenize(text, as: lang).filter { $0.kind == kind }.map {
            String(decoding: u[Int($0.start)..<Int($0.start + $0.length)], as: UTF16.self)
        }
    }

    @Test func detection() {
        #expect(SyntaxHighlighter.detect(fileName: "index.HTML", firstLine: nil) == .html)
        #expect(SyntaxHighlighter.detect(fileName: ".zshrc", firstLine: nil) == .shell)
        #expect(SyntaxHighlighter.detect(fileName: "Makefile", firstLine: nil) == .makefile)
        #expect(SyntaxHighlighter.detect(fileName: "run", firstLine: "#!/usr/bin/env python3") == .python)
        #expect(SyntaxHighlighter.detect(fileName: "deploy", firstLine: "#!/bin/bash") == .shell)
        #expect(SyntaxHighlighter.detect(fileName: "notes.txt", firstLine: "hello") == nil)
    }

    @Test func xml() {
        let s = "<?xml version=\"1.0\"?>\r\n<!-- c -->\r\n<ns:root xmlns:ns=\"u\"><a b='1'/><![CDATA[x<y]]>&lt;</ns:root>"
        #expect(SyntaxHighlighter.detect(fileName: "Strings.resx", firstLine: nil) == .xml)
        #expect(spans(s, .xml, .meta) == ["<?xml"])
        #expect(spans(s, .xml, .comment) == ["<!-- c -->"])
        #expect(spans(s, .xml, .attribute) == ["version", "xmlns:ns", "b"])
        #expect(spans(s, .xml, .string) == ["\"1.0\"", "\"u\"", "'1'", "<![CDATA[x<y]]>"])
        #expect(spans(s, .xml, .tag).contains("<ns:root"))
        #expect(spans(s, .xml, .constant) == ["&lt;"])
    }

    @Test func markupSniffing() {
        #expect(SyntaxHighlighter.detect(fileName: "nuget.config", firstLine: "\u{FEFF}<?xml version=\"1.0\"?>") == .xml)
        #expect(SyntaxHighlighter.detect(fileName: "page", firstLine: "<!DOCTYPE html>") == .html)
        #expect(SyntaxHighlighter.detect(fileName: "app.config", firstLine: "key = value") == nil)
    }

    @Test func textDecoding() {
        let utf16le: [UInt8] = [0xFF, 0xFE] + Array("<?xml?>".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        #expect(QuickPreview.decodeText(utf16le) == "<?xml?>")
        #expect(QuickPreview.decodeText([0xEF, 0xBB, 0xBF] + Array("<a/>".utf8)) == "<a/>")
        #expect(QuickPreview.decodeText([0x41, 0x00, 0x42]) == nil)
    }

    @Test func shell() {
        let s = "# comment\nif [ -n \"$HOME\" ]; then\n  echo ${PATH} $1\nfi\n"
        #expect(spans(s, .shell, .comment) == ["# comment"])
        #expect(spans(s, .shell, .keyword) == ["if", "then", "fi"])
        #expect(spans(s, .shell, .string) == ["\"$HOME\""])
        #expect(spans(s, .shell, .variable) == ["${PATH}", "$1"])
    }

    @Test func html() {
        let s = "<!-- c --><div class=\"a\">&amp;<script>let x = 1;</script><style>p { color: red; }</style></div>"
        #expect(spans(s, .html, .comment) == ["<!-- c -->"])
        #expect(spans(s, .html, .attribute) == ["class"])
        #expect(spans(s, .html, .string) == ["\"a\""])
        #expect(spans(s, .html, .constant) == ["&amp;"])
        #expect(spans(s, .html, .keyword) == ["let"])
        #expect(spans(s, .html, .property) == ["color"])
        #expect(spans(s, .html, .tag).contains("<div"))
    }

    @Test func css() {
        let s = "@media screen { .btn:hover, #id { margin: -4px 10%; color: #fff !important; } }"
        #expect(spans(s, .css, .keyword) == ["@media", "!important"])
        #expect(spans(s, .css, .type) == [".btn", "#id"])
        #expect(spans(s, .css, .property) == ["margin", "color"])
        #expect(spans(s, .css, .number) == ["-4px", "10%", "#fff"])
    }

    @Test func swiftAndJSON() {
        let s = "/// doc\nstruct A { let s = \"\"\"\nhi\n\"\"\"; var n = 0x1F }"
        #expect(spans(s, .swift, .keyword) == ["struct", "let", "var"])
        #expect(spans(s, .swift, .number) == ["0x1F"])
        #expect(spans(s, .swift, .string).count == 1)
        let j = "{\"k\": [1.5e3, true, \"v\"]}"
        #expect(spans(j, .json, .property) == ["\"k\""])
        #expect(spans(j, .json, .string) == ["\"v\""])
        #expect(spans(j, .json, .constant) == ["true"])
    }

    @Test func rustLifetimeIsNotAString() {
        let s = "fn f<'a>(x: &'a str) -> char { 'x' }"
        #expect(spans(s, .rust, .string) == ["'x'"])
    }

    @Test func yamlAndMarkdown() {
        #expect(spans("name: \"x\" # c\nlist:\n  - 3\n", .yaml, .property) == ["name", "list"])
        #expect(spans("# Title\nuse `code` and [link](http://x)\n```\nraw\n```\n", .markdown, .heading) == ["# Title"])
    }

    @Test func throughput() {
        let unit = (try? String(contentsOfFile: #filePath, encoding: .utf8)) ?? "let x = 1\n"
        let text = String(repeating: unit, count: max(1, 256 * 1024 / unit.utf8.count))
        let t0 = Date()
        let tokens = SyntaxHighlighter.tokenize(text, as: .swift)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("tokenize \(text.utf8.count / 1024) KB swift → \(tokens.count) tokens in \(Int(ms)) ms")
        #expect(!tokens.isEmpty)
    }
}
