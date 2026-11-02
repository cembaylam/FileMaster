import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// CGImage is immutable; wrap it to cross actors.
public struct PreviewImage: @unchecked Sendable {
    public let cgImage: CGImage
}

public enum PreviewResult: Sendable {
    case image(PreviewImage, caption: String)
    case text(String, truncated: Bool, highlights: [SyntaxToken])
    case hex(String, totalSize: Int64)
    case message(String)
}

/// First-cut preview pipeline (M2 replaces this with PreviewRouter + Previewer protocol, docs/PREVIEW.md):
/// image → text → QuickLook thumbnail → hex. Runs on the global executor; checks cancellation between steps.
public enum QuickPreview {
    public static let maxTextBytes = 256 * 1024
    static let hexBytes = 4096

    public static func load(path: String, size: Int64, maxPixel: Int, scale: CGFloat) async -> PreviewResult {
        if size == 0 { return .message("Empty file") }
        let url = URL(fileURLWithPath: path)
        let type = UTType(filenameExtension: url.pathExtension)

        if let type, type.conforms(to: .image), let r = image(url, maxPixel: maxPixel) { return r }
        if let type, type.conforms(to: .audiovisualContent) {
            return await media(url, type: type, maxPixel: maxPixel, scale: scale)
        }
        if Task.isCancelled { return .message("") }

        guard let head = readHead(path, max: maxTextBytes) else {
            return .message(String(cString: strerror(errno)))
        }
        if let text = decodeText(head) {
            // isNewline, not "\n": a CRLF is one Character and would not split.
            let firstLine = text.prefix(200).split(maxSplits: 1, whereSeparator: \.isNewline).first
            let tokens = SyntaxHighlighter.detect(fileName: url.lastPathComponent, firstLine: firstLine)
                .map { SyntaxHighlighter.tokenize(text, as: $0) } ?? []
            return .text(text, truncated: Int64(head.count) < size, highlights: tokens)
        }
        if Task.isCancelled { return .message("") }

        if let thumb = await quickLookThumbnail(url, maxPixel: maxPixel, scale: scale) {
            return .image(PreviewImage(cgImage: thumb), caption: type?.localizedDescription ?? "")
        }
        return .hex(hexDump(head.prefix(hexBytes)), totalSize: size)
    }

    static func image(_ url: URL, maxPixel: Int) -> PreviewResult? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        var caption = ""
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            caption = "\(w)×\(h)"
        }
        return .image(PreviewImage(cgImage: img), caption: caption)
    }

    /// Video: poster frame at 10% via AVAssetImageGenerator + "1920×1080 · 3:24 · H.264".
    /// Audio, or anything AVFoundation can't decode: QuickLook (artwork) → info message. Never hex.
    static func media(_ url: URL, type: UTType, maxPixel: Int, scale: CGFloat) async -> PreviewResult {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? .nan
        var info: [String] = []

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let s = size.applying(transform)
                info.append("\(Int(abs(s.width)))×\(Int(abs(s.height)))")
            }
            if duration.isFinite { info.append(formatDuration(duration)) }
            if let desc = try? await track.load(.formatDescriptions).first {
                info.append(codecName(CMFormatDescriptionGetMediaSubType(desc)))
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            let at = CMTime(seconds: duration.isFinite ? duration * 0.1 : 0, preferredTimescale: 600)
            if let frame = try? await generator.image(at: at).image {
                return .image(PreviewImage(cgImage: frame), caption: info.joined(separator: " · "))
            }
        } else if duration.isFinite {
            info.append(formatDuration(duration))
        }
        if Task.isCancelled { return .message("") }

        if let thumb = await quickLookThumbnail(url, maxPixel: maxPixel, scale: scale) {
            return .image(PreviewImage(cgImage: thumb), caption: info.joined(separator: " · "))
        }
        let kind = type.localizedDescription ?? (type.conforms(to: .audio) ? "Audio" : "Video")
        return .message(([kind] + info).joined(separator: " · "))
    }

    static func formatDuration(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        let (h, m, s) = (t / 3600, t / 60 % 60, t % 60)
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
        return "\(m):\(ss)"
    }

    static func codecName(_ fourCC: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((fourCC >> $0) & 0xFF) }
        let code = String(decoding: bytes, as: UTF8.self)
        switch code {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "apcn", "apch", "apcs", "apco", "ap4h", "ap4x": return "ProRes"
        case "mp4v": return "MPEG-4"
        default: return code.trimmingCharacters(in: .whitespaces)
        }
    }

    static func quickLookThumbnail(_ url: URL, maxPixel: Int, scale: CGFloat) async -> CGImage? {
        let side = CGFloat(maxPixel) / scale
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    static func readHead(_ path: String, max: Int) -> [UInt8]? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: max)
        var total = 0
        while total < max {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress! + total, max - total) }
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { break }
            total += n
        }
        buf.removeSubrange(total...)
        return buf
    }

    /// UTF-8 text with no NULs in the first 8 KB. A multi-byte sequence cut by the read limit is tolerated.
    static func decodeText(_ bytes: [UInt8]) -> String? {
        // UTF-16 with BOM (Windows tools often write XML/.reg/.txt this way). Odd trailing byte from the read cut is dropped.
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            let little = bytes[0] == 0xFF
            let units = stride(from: 2, to: bytes.count - 1, by: 2).map {
                little ? UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 : UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
            }
            return String(decoding: units, as: UTF16.self)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return decodeText(Array(bytes.dropFirst(3))) }
        if bytes.prefix(8192).contains(0) { return nil }
        for trim in 0...3 where bytes.count >= trim {
            if let s = String(validating: bytes.dropLast(trim), as: UTF8.self) { return s }
        }
        return nil
    }

    public static func hexDump(_ bytes: ArraySlice<UInt8>, baseOffset: Int = 0) -> String {
        let hex: [UInt8] = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 5)
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let off = baseOffset + (i - bytes.startIndex)
            for shift in stride(from: 28, through: 0, by: -4) { out.append(hex[(off >> shift) & 0xF]) }
            out.append(contentsOf: [32, 32])
            let end = min(i + 16, bytes.endIndex)
            for j in i..<(i + 16) {
                if j < end {
                    out.append(hex[Int(bytes[j] >> 4)]); out.append(hex[Int(bytes[j] & 0xF)])
                } else {
                    out.append(contentsOf: [32, 32])
                }
                out.append(32)
                if j == i + 7 { out.append(32) }
            }
            out.append(contentsOf: Array(" │".utf8))
            for j in i..<end { out.append(bytes[j] >= 0x20 && bytes[j] < 0x7F ? bytes[j] : UInt8(ascii: ".")) }
            out.append(contentsOf: Array("│\n".utf8))
            i = end
        }
        return String(decoding: out, as: UTF8.self)
    }
}
