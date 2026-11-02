/// Fast hand-written tokenizers per language family (docs/PREVIEW.md). Works on UTF-16 code units so token
/// ranges map 1:1 onto NSAttributedString ranges. Only "interesting" spans are emitted; plain text is not.
public enum SyntaxKind: UInt8, Sendable {
    case keyword, type, string, number, comment, tag, attribute, property, variable, meta, constant
    case inserted, deleted, heading
}

public struct SyntaxToken: Sendable, Equatable {
    public let start: Int32
    public let length: Int32
    public let kind: SyntaxKind
}

public enum Language: String, Sendable, CaseIterable {
    case swift, c, cpp, objc, javascript, typescript, java, kotlin, go, rust, csharp, php, python, ruby
    case shell, lua, sql, perl, dart, scala, zig, r, makefile, dockerfile
    case html, xml, css, scss, json, yaml, toml, ini, markdown, diff
}

public enum SyntaxHighlighter {
    public static func tokenize(_ text: String, as language: Language) -> [SyntaxToken] {
        var lexer = Lexer(Array(text.utf16))
        let end = lexer.u.count
        switch language {
        case .html: lexer.markup(0, end, html: true)
        case .xml: lexer.markup(0, end, html: false)
        case .css: lexer.css(0, end, scss: false)
        case .scss: lexer.css(0, end, scss: true)
        case .json: lexer.json(0, end)
        case .yaml: lexer.lines(0, end) { l, s, e in l.yamlLine(s, e) }
        case .toml, .ini: lexer.lines(0, end) { l, s, e in l.iniLine(s, e) }
        case .markdown: lexer.markdown(0, end)
        case .diff: lexer.lines(0, end) { l, s, e in l.diffLine(s, e) }
        default: lexer.code(0, end, CodeSpec.for(language))
        }
        return lexer.tokens
    }

    // MARK: Detection

    public static func detect(fileName: String, firstLine: Substring?) -> Language? {
        let lower = fileName.lowercased()
        if let l = byName[lower] { return l }
        if let dot = lower.lastIndex(of: "."), dot != lower.startIndex,
           let l = byExtension[String(lower[lower.index(after: dot)...])] {
            return l
        }
        if let line = firstLine, line.hasPrefix("#!") {
            if line.contains("python") { return .python }
            if line.contains("node") || line.contains("deno") || line.contains("bun") { return .javascript }
            if line.contains("ruby") { return .ruby }
            if line.contains("perl") { return .perl }
            if line.contains("lua") { return .lua }
            if line.contains("php") { return .php }
            if line.contains("sh") { return .shell } // sh, bash, zsh, fish, ksh, dash
        }
        // Content sniffing for markup with an unknown extension (nuget.config, .resx, .xaml, ...).
        if let line = firstLine?.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace }) {
            let head = line.prefix(16).lowercased()
            if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") { return .html }
            if head.hasPrefix("<?xml") || head.hasPrefix("<!doctype") || head.hasPrefix("<svg")
                || head.hasPrefix("<plist") || head.hasPrefix("<!--") { return .xml }
        }
        return nil
    }

    static let byExtension: [String: Language] = {
        var m: [String: Language] = [:]
        func add(_ l: Language, _ exts: String) { for e in exts.split(separator: " ") { m[String(e)] = l } }
        add(.swift, "swift swiftinterface")
        add(.c, "c h")
        add(.cpp, "cpp cc cxx c++ hpp hh hxx ino cu metal")
        add(.objc, "m mm")
        add(.javascript, "js mjs cjs jsx")
        add(.typescript, "ts tsx mts cts")
        add(.java, "java gradle groovy")
        add(.kotlin, "kt kts")
        add(.go, "go")
        add(.rust, "rs")
        add(.csharp, "cs")
        add(.php, "php phtml")
        add(.python, "py pyw pyi")
        add(.ruby, "rb rake gemspec podspec")
        add(.shell, "sh bash zsh fish ksh command tool cmake env")
        add(.lua, "lua")
        add(.sql, "sql")
        add(.perl, "pl pm")
        add(.dart, "dart")
        add(.scala, "scala sc")
        add(.zig, "zig")
        add(.r, "r")
        add(.makefile, "mk mak make")
        add(.dockerfile, "dockerfile")
        add(.html, "html htm xhtml vue svelte")
        add(.xml, "xml svg plist xib storyboard xsd xsl xslt rss atom entitlements xcscheme xcworkspacedata "
            + "csproj vbproj fsproj vcxproj props targets nuspec resx xaml axaml "
            + "pom wsdl xliff xlf gpx kml tmx dae opml musicxml fxml mobileconfig xul jnlp")
        add(.css, "css")
        add(.scss, "scss sass less")
        add(.json, "json jsonc json5 geojson webmanifest ipynb babelrc eslintrc")
        add(.yaml, "yaml yml")
        add(.toml, "toml lock")
        add(.ini, "ini cfg conf properties gitconfig")
        add(.markdown, "md markdown mdx")
        add(.diff, "diff patch")
        return m
    }()

    static let byName: [String: Language] = {
        var m: [String: Language] = [:]
        func add(_ l: Language, _ names: String) { for n in names.split(separator: " ") { m[String(n)] = l } }
        add(.makefile, "makefile gnumakefile justfile")
        add(.dockerfile, "dockerfile containerfile")
        add(.shell, ".bashrc .bash_profile .bash_aliases .bash_logout .zshrc .zprofile .zshenv .zlogin .profile .env .envrc cmakelists.txt")
        add(.ruby, "gemfile podfile rakefile vagrantfile brewfile fastfile appfile")
        add(.ini, ".gitconfig .gitmodules .editorconfig .npmrc")
        add(.json, ".prettierrc")
        return m
    }()
}

// MARK: - Language specs for the generic code lexer

struct CodeSpec {
    var lineComments: [[UInt16]] = []
    var block: (open: [UInt16], close: [UInt16])?
    var quotes: Set<UInt16> = [C.quote, C.apos]
    var multilineQuotes: Set<UInt16> = [C.backtick]
    /// `'` only starts a short char literal ('x', '\n'); otherwise ignored (Rust lifetimes, Swift none).
    var charQuote = false
    var triple = false
    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = ["true", "false", "null"]
    var capitalizedTypes = false
    var variablePrefixes: Set<UInt16> = []
    /// `#` at line start → meta to end of line (C preprocessor, Swift `#if`, Rust `#[…]`).
    var preprocessor = false
    var decorators = false
    var caseInsensitive = false

    static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    static let slashes = Array("//".utf16), hash = Array("#".utf16), dashes = Array("--".utf16)
    static let cBlock = (Array("/*".utf16), Array("*/".utf16))

    static func cLike(_ keywords: String, types: String = "", constants: String = "true false null") -> CodeSpec {
        var s = CodeSpec()
        s.lineComments = [slashes]
        s.block = cBlock
        s.keywords = words(keywords)
        s.types = words(types)
        s.constants = words(constants)
        s.charQuote = true
        s.capitalizedTypes = true
        return s
    }

    static func hashCommented(_ keywords: String, constants: String = "true false") -> CodeSpec {
        var s = CodeSpec()
        s.lineComments = [hash]
        s.keywords = words(keywords)
        s.constants = words(constants)
        return s
    }

    static let cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Bool bool"
    static let cTypes = "size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t FILE"
    static let jsKeywords = "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set from as"

    static let javascript: CodeSpec = {
        var s = cLike(jsKeywords, constants: "true false null undefined NaN Infinity")
        s.quotes = [C.quote, C.apos, C.backtick]
        s.charQuote = false
        s.decorators = true
        return s
    }()

    static let shellSpec: CodeSpec = {
        var s = hashCommented("if then else elif fi for while until do done case esac function in select return local export readonly declare typeset unset shift source alias exit break continue eval exec trap set time coproc")
        s.types = words("echo printf read cd pwd test cat grep sed awk ls rm cp mv mkdir chmod chown sudo brew git curl wget find xargs sort uniq head tail tr cut tee touch ln kill ps make npm node python3 python pip swift open defaults")
        s.quotes = [C.quote, C.apos, C.backtick]
        s.multilineQuotes = [C.quote, C.apos, C.backtick]
        s.variablePrefixes = [C.dollar]
        return s
    }()

    static func `for`(_ language: Language) -> CodeSpec {
        switch language {
        case .c:
            var s = cLike(cKeywords, types: cTypes, constants: "NULL true false")
            s.preprocessor = true
            s.capitalizedTypes = false
            return s
        case .cpp:
            var s = cLike(cKeywords + " class namespace template typename public private protected virtual override final new delete this throw try catch using operator friend explicit mutable constexpr consteval noexcept static_cast dynamic_cast reinterpret_cast const_cast decltype co_await co_return co_yield concept requires",
                          types: cTypes + " std string vector map set unique_ptr shared_ptr", constants: "nullptr NULL true false")
            s.preprocessor = true
            return s
        case .objc:
            var s = cLike(cKeywords + " self super id instancetype nonatomic atomic strong weak assign copy readonly readwrite nullable nonnull",
                          types: cTypes, constants: "nil Nil YES NO NULL true false")
            s.preprocessor = true
            s.decorators = true
            return s
        case .swift:
            var s = cLike("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as await async throws is try super self Self some any actor nonisolated isolated mutating nonmutating override final lazy weak unowned convenience required dynamic indirect optional get set willSet didSet consuming borrowing sending macro package",
                          constants: "true false nil")
            s.quotes = [C.quote]
            s.charQuote = false
            s.triple = true
            s.decorators = true
            s.preprocessor = true
            return s
        case .javascript:
            return javascript
        case .typescript:
            var s = javascript
            s.keywords.formUnion(words("interface type enum implements namespace declare abstract private protected public readonly keyof infer is module satisfies override"))
            s.types = words("string number boolean object symbol bigint void any unknown never")
            return s
        case .java:
            var s = cLike("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try var void volatile while record sealed permits yield def",
                          types: "boolean byte char double float int long short")
            s.decorators = true
            return s
        case .kotlin:
            var s = cLike("as break class continue do else for fun if in interface is object package return super this throw try typealias typeof val var when while by catch constructor finally get import init set where abstract annotation companion const crossinline data enum external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg")
            s.triple = true
            s.decorators = true
            return s
        case .go:
            var s = cLike("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var",
                          types: "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any",
                          constants: "true false nil iota")
            s.quotes = [C.quote, C.apos, C.backtick]
            s.capitalizedTypes = false
            return s
        case .rust:
            var s = cLike("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while macro_rules union",
                          types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
                          constants: "true false None Some Ok Err")
            s.preprocessor = true
            return s
        case .csharp:
            var s = cLike("abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual void volatile while async await var get set value record init yield partial where",
                          types: "bool byte char decimal double float int long object sbyte short string uint ulong ushort dynamic")
            s.preprocessor = true
            return s
        case .php:
            var s = cLike("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield",
                          constants: "true false null TRUE FALSE NULL")
            s.lineComments = [slashes, hash]
            s.charQuote = false
            s.variablePrefixes = [C.dollar]
            return s
        case .python:
            var s = hashCommented("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case",
                                  constants: "True False None self cls")
            s.types = words("int float str bool list dict set tuple bytes object")
            s.triple = true
            s.decorators = true
            s.capitalizedTypes = true
            return s
        case .ruby:
            var s = hashCommented("BEGIN END alias and begin break case class def do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer private protected public include extend lambda proc raise puts",
                                  constants: "true false nil")
            s.variablePrefixes = [C.at, C.dollar]
            s.capitalizedTypes = true
            return s
        case .shell:
            return shellSpec
        case .makefile:
            var s = shellSpec
            s.keywords.formUnion(words("ifeq ifneq ifdef ifndef endif include define endef override vpath"))
            return s
        case .dockerfile:
            var s = shellSpec
            s.keywords.formUnion(words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS MAINTAINER"))
            return s
        case .lua:
            var s = CodeSpec()
            s.lineComments = [dashes]
            s.block = (Array("--[[".utf16), Array("]]".utf16))
            s.keywords = words("and break do else elseif end for function goto if in local not or repeat return then until while")
            s.constants = words("true false nil self")
            return s
        case .sql:
            var s = CodeSpec()
            s.lineComments = [dashes]
            s.block = cBlock
            s.caseInsensitive = true
            s.keywords = words("select from where insert into values update set delete create table drop alter add column index view join inner left right outer full cross on as and or not is in exists between like ilike limit offset order by group having distinct union all case when then else end primary key foreign references default unique check constraint begin commit rollback transaction with returning if replace trigger database schema grant revoke asc desc count sum avg min max cast coalesce pragma")
            s.types = words("int integer bigint smallint text varchar char boolean bool date timestamp timestamptz time real float double numeric decimal blob serial uuid json jsonb")
            return s
        case .perl:
            var s = hashCommented("my our local sub if elsif else unless while until for foreach do last next redo return use require package print die eq ne lt gt le ge and or not")
            s.variablePrefixes = [C.dollar, C.at, C.percent]
            return s
        case .dart:
            var s = cLike("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var void while with yield")
            s.charQuote = false
            s.triple = true
            s.decorators = true
            return s
        case .scala:
            var s = cLike("abstract case catch class def do else extends final finally for forSome if implicit import lazy match new object override package private protected return sealed super this throw trait try type val var while with yield given using enum then export")
            s.triple = true
            s.decorators = true
            return s
        case .zig:
            return cLike("addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while",
                         constants: "true false null undefined")
        case .r:
            return hashCommented("if else repeat while function for next break in return library require",
                                 constants: "TRUE FALSE NULL NA Inf NaN T F")
        default:
            return CodeSpec()
        }
    }
}

// MARK: - Code units

enum C {
    static let tab: UInt16 = 9, nl: UInt16 = 10, cr: UInt16 = 13, sp: UInt16 = 32, bang: UInt16 = 33
    static let quote: UInt16 = 34, hash: UInt16 = 35, dollar: UInt16 = 36, percent: UInt16 = 37, amp: UInt16 = 38
    static let apos: UInt16 = 39, lparen: UInt16 = 40, rparen: UInt16 = 41, star: UInt16 = 42, plus: UInt16 = 43
    static let minus: UInt16 = 45, dot: UInt16 = 46, slash: UInt16 = 47, colon: UInt16 = 58, semi: UInt16 = 59
    static let lt: UInt16 = 60, eq: UInt16 = 61, gt: UInt16 = 62, question: UInt16 = 63, at: UInt16 = 64
    static let lbrack: UInt16 = 91, backslash: UInt16 = 92, rbrack: UInt16 = 93, backtick: UInt16 = 96
    static let lbrace: UInt16 = 123, rbrace: UInt16 = 125, tilde: UInt16 = 126, pipe: UInt16 = 124
}

@inline(__always) func isDigit(_ c: UInt16) -> Bool { c &- 48 < 10 }
@inline(__always) func isUpper(_ c: UInt16) -> Bool { c &- 65 < 26 }
@inline(__always) func isIdentStart(_ c: UInt16) -> Bool { (c | 0x20) &- 97 < 26 || c == 95 || c >= 0x80 }
@inline(__always) func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
@inline(__always) func isBlank(_ c: UInt16) -> Bool { c == C.sp || c == C.tab || c == C.cr }

// MARK: - Lexer

struct Lexer {
    let u: [UInt16]
    var tokens: [SyntaxToken] = []

    init(_ units: [UInt16]) {
        u = units
        tokens.reserveCapacity(units.count / 8)
    }

    @inline(__always)
    mutating func emit(_ s: Int, _ e: Int, _ k: SyntaxKind) {
        if e > s { tokens.append(SyntaxToken(start: Int32(s), length: Int32(e - s), kind: k)) }
    }

    @inline(__always)
    func starts(_ s: [UInt16], _ i: Int, _ end: Int) -> Bool {
        guard i + s.count <= end else { return false }
        for k in 0..<s.count where u[i + k] != s[k] { return false }
        return true
    }

    func find(_ s: [UInt16], _ from: Int, _ end: Int, caseInsensitive: Bool = false) -> Int? {
        guard let first = s.first, s.count <= end - from else { return nil }
        var i = from
        while i + s.count <= end {
            let c = caseInsensitive ? (u[i] | (isUpper(u[i]) ? 0x20 : 0)) : u[i]
            if c == first {
                var ok = true
                for k in 1..<s.count {
                    let d = caseInsensitive && isUpper(u[i + k]) ? u[i + k] | 0x20 : u[i + k]
                    if d != s[k] { ok = false; break }
                }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    func lineEnd(_ i: Int, _ end: Int) -> Int {
        var j = i
        while j < end && u[j] != C.nl { j += 1 }
        return j
    }

    func word(_ s: Int, _ e: Int) -> String { String(decoding: u[s..<e], as: UTF16.self) }

    /// Runs `body(lexer, lineStart, lineEnd)` per line.
    mutating func lines(_ from: Int, _ end: Int, _ body: (inout Lexer, Int, Int) -> Void) {
        var i = from
        while i < end {
            let e = lineEnd(i, end)
            body(&self, i, e)
            i = e + 1
        }
    }

    // MARK: Generic code

    mutating func code(_ from: Int, _ end: Int, _ spec: CodeSpec) {
        var i = from
        var lineStart = true
        while i < end {
            let c = u[i]
            if c == C.nl { lineStart = true; i += 1; continue }
            if isBlank(c) { i += 1; continue }
            let atLineStart = lineStart
            lineStart = false

            if spec.preprocessor && atLineStart && c == C.hash {
                let e = lineEnd(i, end)
                emit(i, e, .meta)
                i = e
                continue
            }
            if let b = spec.block, starts(b.open, i, end) {
                let e = find(b.close, i + b.open.count, end).map { $0 + b.close.count } ?? end
                emit(i, e, .comment)
                i = e
                continue
            }
            if spec.lineComments.contains(where: { starts($0, i, end) }) {
                let e = lineEnd(i, end)
                emit(i, e, .comment)
                i = e
                continue
            }
            if spec.quotes.contains(c) {
                i = string(i, end, quote: c, spec: spec)
                continue
            }
            if isDigit(c) || (c == C.dot && i + 1 < end && isDigit(u[i + 1])) {
                var j = i + 1
                while j < end && (isIdent(u[j]) || (u[j] == C.dot && j + 1 < end && isDigit(u[j + 1]))) { j += 1 }
                emit(i, j, .number)
                i = j
                continue
            }
            if spec.variablePrefixes.contains(c) && i + 1 < end, let j = variableEnd(i, end) {
                emit(i, j, .variable)
                i = j
                continue
            }
            if spec.decorators && c == C.at && i + 1 < end && isIdentStart(u[i + 1]) {
                var j = i + 1
                while j < end && (isIdent(u[j]) || u[j] == C.dot) { j += 1 }
                emit(i, j, .meta)
                i = j
                continue
            }
            if isIdentStart(c) {
                var j = i + 1
                while j < end && isIdent(u[j]) { j += 1 }
                if let k = classify(i, j, spec) { emit(i, j, k) }
                i = j
                continue
            }
            i += 1
        }
    }

    private mutating func string(_ i: Int, _ end: Int, quote c: UInt16, spec: CodeSpec) -> Int {
        if spec.triple && i + 2 < end && u[i + 1] == c && u[i + 2] == c {
            let e = find([c, c, c], i + 3, end).map { $0 + 3 } ?? end
            emit(i, e, .string)
            return e
        }
        if c == C.apos && spec.charQuote {
            // 'x', '😀' (surrogate pair) or an escape like '\n' / '\u{1F600}'; anything else ('a lifetimes) isn't a string.
            if i + 1 < end && u[i + 1] == C.backslash {
                var j = i + 2
                while j < end && j <= i + 12 && u[j] != C.nl {
                    if u[j] == C.apos { emit(i, j + 1, .string); return j + 1 }
                    j += 1
                }
            } else {
                let close = i + 1 < end && UTF16.isLeadSurrogate(u[i + 1]) ? i + 3 : i + 2
                if close < end && u[close] == C.apos { emit(i, close + 1, .string); return close + 1 }
            }
            return i + 1
        }
        let multiline = spec.multilineQuotes.contains(c)
        var j = i + 1
        while j < end {
            let d = u[j]
            if d == C.backslash { j += 2; continue }
            if d == c { j += 1; break }
            if d == C.nl && !multiline { break }
            j += 1
        }
        j = min(j, end)
        emit(i, j, .string)
        return j
    }

    /// `$foo`, `${…}`, `$(…)`, `$1`, `$?`, `@ivar`.
    private func variableEnd(_ i: Int, _ end: Int) -> Int? {
        let n = u[i + 1]
        var j = i + 1
        if n == C.lbrace || n == C.lparen {
            let close = n == C.lbrace ? C.rbrace : C.rparen
            while j < end && u[j] != close && u[j] != C.nl { j += 1 }
            return min(j + 1, end)
        }
        if isIdentStart(n) || (u[i] == C.at && n == C.at) {
            j += 1
            while j < end && isIdent(u[j]) { j += 1 }
            return j
        }
        if u[i] == C.dollar && (isDigit(n) || [C.hash, C.at, C.question, C.star, C.bang, C.dollar, C.minus].contains(n)) {
            return i + 2
        }
        return nil
    }

    private func classify(_ s: Int, _ e: Int, _ spec: CodeSpec) -> SyntaxKind? {
        if e - s > 24 { return spec.capitalizedTypes && isUpper(u[s]) ? .type : nil }
        var w = word(s, e)
        if spec.caseInsensitive { w = w.lowercased() }
        if spec.keywords.contains(w) { return .keyword }
        if spec.constants.contains(w) { return .constant }
        if spec.types.contains(w) { return .type }
        if spec.capitalizedTypes && isUpper(u[s]) { return .type }
        return nil
    }

    // MARK: HTML / XML

    mutating func markup(_ from: Int, _ end: Int, html: Bool) {
        let commentOpen = Array("<!--".utf16), commentClose = Array("-->".utf16)
        let cdataOpen = Array("<![CDATA[".utf16), cdataClose = Array("]]>".utf16)
        var i = from
        while i < end {
            let c = u[i]
            if c == C.lt {
                if starts(commentOpen, i, end) {
                    let e = find(commentClose, i + 4, end).map { $0 + 3 } ?? end
                    emit(i, e, .comment)
                    i = e
                } else if starts(cdataOpen, i, end) {
                    let e = find(cdataClose, i + 9, end).map { $0 + 3 } ?? end
                    emit(i, e, .string)
                    i = e
                } else if i + 1 < end, isIdentStart(u[i + 1]) || [C.slash, C.question, C.bang].contains(u[i + 1]) {
                    i = tag(i, end, html: html)
                } else {
                    i += 1
                }
                continue
            }
            if c == C.amp {
                var j = i + 1
                while j < end && j < i + 12 && (isIdent(u[j]) || u[j] == C.hash) { j += 1 }
                if j < end && u[j] == C.semi && j > i + 1 {
                    emit(i, j + 1, .constant)
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
    }

    private mutating func tag(_ start: Int, _ end: Int, html: Bool) -> Int {
        var i = start + 1
        let closing = u[i] == C.slash
        if closing || u[i] == C.question || u[i] == C.bang { i += 1 }
        let nameStart = i
        while i < end && (isIdent(u[i]) || u[i] == C.colon || u[i] == C.minus || u[i] == C.dot) { i += 1 }
        let name = word(nameStart, i).lowercased()
        emit(start, i, u[start + 1] == C.question || u[start + 1] == C.bang ? .meta : .tag)
        var selfClosing = false
        while i < end {
            let c = u[i]
            if c == C.gt { emit(i, i + 1, .tag); i += 1; break }
            if (c == C.slash || c == C.question) && i + 1 < end && u[i + 1] == C.gt {
                emit(i, i + 2, .tag)
                i += 2
                selfClosing = true
                break
            }
            if c == C.quote || c == C.apos {
                var j = i + 1
                while j < end && u[j] != c { j += 1 }
                j = min(j + 1, end)
                emit(i, j, .string)
                i = j
                continue
            }
            if isIdentStart(c) {
                var j = i
                while j < end && (isIdent(u[j]) || u[j] == C.minus || u[j] == C.colon || u[j] == C.dot) { j += 1 }
                emit(i, j, .attribute)
                i = j
                continue
            }
            if c == C.lt { break }
            i += 1
        }
        if html && !closing && !selfClosing && (name == "script" || name == "style") {
            let bodyEnd = find(Array("</\(name)".utf16), i, end, caseInsensitive: true) ?? end
            if name == "script" { code(i, bodyEnd, CodeSpec.javascript) } else { css(i, bodyEnd, scss: false) }
            return bodyEnd
        }
        return i
    }

    // MARK: CSS / SCSS

    mutating func css(_ from: Int, _ end: Int, scss: Bool) {
        var i = from
        var depth = 0
        var inValue = false
        @inline(__always) func identEnd(_ j0: Int) -> Int {
            var j = j0
            while j < end && (isIdent(u[j]) || u[j] == C.minus) { j += 1 }
            return j
        }
        /// Inside a block, `a:b` is a declaration if `;`/`}` comes before `{`, else a selector (`a:hover {`).
        func isDeclaration(_ from: Int) -> Bool {
            var j = from
            while j < end {
                switch u[j] {
                case C.lbrace: return false
                case C.semi, C.rbrace: return true
                default: j += 1
                }
            }
            return true
        }
        while i < end {
            let c = u[i]
            let next: UInt16 = i + 1 < end ? u[i + 1] : 0
            if c == C.slash && next == C.star {
                let e = find(Array("*/".utf16), i + 2, end).map { $0 + 2 } ?? end
                emit(i, e, .comment); i = e; continue
            }
            if scss && c == C.slash && next == C.slash {
                let e = lineEnd(i, end)
                emit(i, e, .comment); i = e; continue
            }
            switch c {
            case C.quote, C.apos:
                var j = i + 1
                while j < end && u[j] != c && u[j] != C.nl { if u[j] == C.backslash { j += 1 }; j += 1 }
                j = min(j + 1, end)
                emit(i, j, .string); i = j
            case C.lbrace: depth += 1; inValue = false; i += 1
            case C.rbrace: depth = max(0, depth - 1); inValue = false; i += 1
            case C.semi: inValue = false; i += 1
            case C.at:
                let j = identEnd(i + 1)
                emit(i, j, .keyword); i = j
            case C.dollar where scss:
                let j = identEnd(i + 1)
                emit(i, j, .variable); i = j
            case C.minus where next == C.minus:
                let j = identEnd(i + 2)
                emit(i, j, .variable); i = j
            case C.bang:
                let j = identEnd(i + 1)
                emit(i, j, .keyword); i = j
            case C.hash:
                let j = identEnd(i + 1)
                emit(i, j, inValue ? .number : .type); i = j
            case C.colon:
                if depth > 0 && !inValue && isDeclaration(i) {
                    inValue = true
                    i += 1
                } else if !inValue {
                    var j = i + 1
                    if j < end && u[j] == C.colon { j += 1 }
                    j = identEnd(j)
                    emit(i, j, .meta); i = j
                } else {
                    i += 1
                }
            case C.dot where !isDigit(next) && !inValue:
                let j = identEnd(i + 1)
                emit(i, j, .type); i = max(j, i + 1)
            default:
                if isDigit(c) || (c == C.dot && isDigit(next)) || (c == C.minus && isDigit(next) && inValue) {
                    var j = i + 1
                    while j < end && (isIdent(u[j]) || u[j] == C.dot || u[j] == C.percent) { j += 1 }
                    emit(i, j, .number); i = j
                } else if isIdentStart(c) {
                    let j = identEnd(i + 1)
                    if inValue {
                        if j < end && u[j] == C.lparen { emit(i, j, .meta) }
                    } else if depth == 0 {
                        emit(i, j, .tag)
                    } else {
                        var k = j
                        while k < end && isBlank(u[k]) { k += 1 }
                        emit(i, j, k < end && u[k] == C.colon && isDeclaration(k) ? .property : .tag)
                    }
                    i = j
                } else {
                    i += 1
                }
            }
        }
    }

    // MARK: JSON

    mutating func json(_ from: Int, _ end: Int) {
        var i = from
        while i < end {
            let c = u[i]
            if c == C.quote {
                var j = i + 1
                while j < end && u[j] != C.quote { if u[j] == C.backslash { j += 1 }; j += 1 }
                j = min(j + 1, end)
                var k = j
                while k < end && (isBlank(u[k]) || u[k] == C.nl) { k += 1 }
                emit(i, j, k < end && u[k] == C.colon ? .property : .string)
                i = j
            } else if isDigit(c) || (c == C.minus && i + 1 < end && isDigit(u[i + 1])) {
                var j = i + 1
                while j < end && (isDigit(u[j]) || [C.dot, C.minus, C.plus].contains(u[j]) || (u[j] | 0x20) == 101) { j += 1 }
                emit(i, j, .number); i = j
            } else if isIdentStart(c) {
                var j = i + 1
                while j < end && isIdent(u[j]) { j += 1 }
                emit(i, j, .constant); i = j
            } else if c == C.slash && i + 1 < end && u[i + 1] == C.slash {
                let e = lineEnd(i, end)
                emit(i, e, .comment); i = e
            } else {
                i += 1
            }
        }
    }

    // MARK: Line-based formats

    /// Values in YAML/TOML/INI: strings, numbers, constants, trailing comments.
    private mutating func scalar(_ from: Int, _ end: Int, comments: Set<UInt16>) {
        var i = from
        while i < end {
            let c = u[i]
            if comments.contains(c) && (i == from || isBlank(u[i - 1])) {
                emit(i, end, .comment); return
            }
            if c == C.quote || c == C.apos {
                var j = i + 1
                while j < end && u[j] != c { if u[j] == C.backslash && c == C.quote { j += 1 }; j += 1 }
                j = min(j + 1, end)
                emit(i, j, .string); i = j; continue
            }
            if c == C.amp || c == C.star, i + 1 < end, isIdentStart(u[i + 1]), i == from || isBlank(u[i - 1]) {
                var j = i + 1
                while j < end && (isIdent(u[j]) || u[j] == C.minus) { j += 1 }
                emit(i, j, .variable); i = j; continue
            }
            if isDigit(c) || ((c == C.minus || c == C.plus) && i + 1 < end && isDigit(u[i + 1])) {
                var j = i + 1
                while j < end && !isBlank(u[j]) && u[j] != C.comma && u[j] != C.rbrack && u[j] != C.rbrace { j += 1 }
                emit(i, j, .number); i = j; continue
            }
            if isIdentStart(c) {
                var j = i + 1
                while j < end && isIdent(u[j]) { j += 1 }
                switch word(i, j).lowercased() {
                case "true", "false", "null", "yes", "no", "on", "off", "nil", "none", "~": emit(i, j, .constant)
                default: break
                }
                i = j; continue
            }
            i += 1
        }
    }

    mutating func yamlLine(_ s: Int, _ e: Int) {
        var i = s
        while i < e && isBlank(u[i]) { i += 1 }
        guard i < e else { return }
        if u[i] == C.hash { emit(i, e, .comment); return }
        if e - i >= 3 && (starts(Array("---".utf16), i, e) || starts(Array("...".utf16), i, e)) { emit(i, e, .meta); return }
        if u[i] == C.minus && (i + 1 == e || isBlank(u[i + 1])) {
            emit(i, i + 1, .keyword)
            i += 1
            while i < e && isBlank(u[i]) { i += 1 }
        }
        // key: value
        var j = i
        if j < e && (u[j] == C.quote || u[j] == C.apos) {
            let q = u[j]; j += 1
            while j < e && u[j] != q { j += 1 }
            j += 1
        }
        while j < e && !(u[j] == C.colon && (j + 1 == e || isBlank(u[j + 1]))) && u[j] != C.hash { j += 1 }
        if j < e && u[j] == C.colon {
            emit(i, j, .property)
            i = j + 1
        }
        scalar(i, e, comments: [C.hash])
    }

    mutating func iniLine(_ s: Int, _ e: Int) {
        var i = s
        while i < e && isBlank(u[i]) { i += 1 }
        guard i < e else { return }
        if u[i] == C.hash || u[i] == C.semi { emit(i, e, .comment); return }
        if u[i] == C.lbrack {
            var j = i
            while j < e && u[j] != C.rbrack { j += 1 }
            emit(i, min(j + 1, e), .tag)
            scalar(min(j + 1, e), e, comments: [C.hash, C.semi])
            return
        }
        var j = i
        while j < e && u[j] != C.eq && u[j] != C.colon { j += 1 }
        if j < e {
            var k = j
            while k > i && isBlank(u[k - 1]) { k -= 1 }
            emit(i, k, .property)
            scalar(j + 1, e, comments: [C.hash, C.semi])
        }
    }

    mutating func diffLine(_ s: Int, _ e: Int) {
        guard s < e else { return }
        let c = u[s]
        if starts(Array("+++".utf16), s, e) || starts(Array("---".utf16), s, e)
            || starts(Array("diff ".utf16), s, e) || starts(Array("index ".utf16), s, e) {
            emit(s, e, .keyword)
        } else if starts(Array("@@".utf16), s, e) {
            emit(s, e, .meta)
        } else if c == C.plus {
            emit(s, e, .inserted)
        } else if c == C.minus {
            emit(s, e, .deleted)
        }
    }

    // MARK: Markdown

    mutating func markdown(_ from: Int, _ end: Int) {
        let fence1 = Array("```".utf16), fence2 = Array("~~~".utf16)
        var inFence = false
        lines(from, end) { l, s, e in
            var i = s
            while i < e && isBlank(l.u[i]) { i += 1 }
            if l.starts(fence1, i, e) || l.starts(fence2, i, e) {
                inFence.toggle()
                l.emit(s, e, .meta)
                return
            }
            if inFence { l.emit(s, e, .string); return }
            guard i < e else { return }
            let c = l.u[i]
            if c == C.hash {
                l.emit(i, e, .heading); return
            }
            if c == C.gt { l.emit(i, e, .comment); return }
            if (c == C.minus || c == C.star || c == C.plus) && i + 1 < e && isBlank(l.u[i + 1]) {
                l.emit(i, i + 1, .keyword)
            } else if isDigit(c) {
                var j = i
                while j < e && isDigit(l.u[j]) { j += 1 }
                if j < e && (l.u[j] == C.dot || l.u[j] == C.rparen) { l.emit(i, j + 1, .keyword) }
            }
            l.markdownInline(i, e)
        }
    }

    private mutating func markdownInline(_ from: Int, _ end: Int) {
        var i = from
        while i < end {
            let c = u[i]
            if c == C.backtick {
                var j = i + 1
                while j < end && u[j] != C.backtick { j += 1 }
                if j < end { emit(i, j + 1, .string); i = j + 1; continue }
            }
            if c == C.lbrack {
                var j = i + 1
                while j < end && u[j] != C.rbrack { j += 1 }
                if j + 1 < end && u[j + 1] == C.lparen {
                    var k = j + 2
                    while k < end && u[k] != C.rparen { k += 1 }
                    emit(i, j + 1, .tag)
                    emit(j + 1, min(k + 1, end), .attribute)
                    i = k + 1
                    continue
                }
            }
            i += 1
        }
    }
}

extension C {
    static let comma: UInt16 = 44
}
