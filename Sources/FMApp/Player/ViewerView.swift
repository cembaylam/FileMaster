import AVFoundation
import AVKit
import AppKit
import FMPreview
import PDFKit
import UniformTypeIdentifiers

/// Full viewer (Space): replaces the column area. Video/audio → AVPlayer, PDF → PDFKit,
/// everything else → the preview renderer at full size. The FFmpeg backend for formats AVFoundation
/// can't open lands in M3 (docs/MEDIA.md).
@MainActor
final class ViewerView: NSView {
    private let player = AVPlayer()
    private let playerView = PassivePlayerView()
    private let pdfView = PassivePDFView()
    private let content = PreviewPaneView()
    private var task: Task<Void, Never>?
    private var generation = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        for v in [playerView, pdfView, content] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        for v in [playerView, pdfView, content] as [NSView] { v.frame = bounds }
    }

    /// True while a playable audio/video item is loaded.
    var hasMedia: Bool { !playerView.isHidden && player.currentItem != nil }

    func show(path: String, size: Int64) {
        generation &+= 1
        task?.cancel()
        stop()
        let url = URL(fileURLWithPath: path)
        let type = UTType(filenameExtension: url.pathExtension)

        if let type, type.conforms(to: .audiovisualContent) {
            reveal(playerView, background: .black)
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
            let generation = self.generation
            task = Task { [weak self] in
                let playable = (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
                guard let self, !playable, generation == self.generation else { return }
                self.stop()
                self.showGeneric(path: path, size: size,
                                 note: "AVFoundation can't play this format yet. The FFmpeg backend comes in M3.")
            }
            return
        }
        if let type, type.conforms(to: .pdf), let doc = PDFDocument(url: url) {
            pdfView.document = doc
            reveal(pdfView, background: .controlBackgroundColor)
            return
        }
        showGeneric(path: path, size: size, note: nil)
    }

    private func showGeneric(path: String, size: Int64, note: String?) {
        reveal(content, background: .controlBackgroundColor)
        content.showNothing()
        let generation = self.generation
        let scale = window?.backingScaleFactor ?? 2
        let maxPixel = Int(max(bounds.width, bounds.height) * scale)
        task = Task { [weak self] in
            let result = await QuickPreview.load(path: path, size: size, maxPixel: maxPixel, scale: scale)
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            if let note, case .hex = result {
                self.content.show(.message(note))
            } else {
                self.content.show(result)
            }
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        pdfView.document = nil
        pdfView.autoScales = true
    }

    func close() {
        generation &+= 1
        task?.cancel()
        stop()
        content.showNothing()
    }

    private func reveal(_ view: NSView, background: NSColor) {
        for v in [playerView, pdfView, content] as [NSView] { v.isHidden = v !== view }
        layer?.backgroundColor = background.cgColor
    }

    // MARK: Player controls (docs/MEDIA.md §3)

    func togglePlay() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func seek(by seconds: Double) {
        guard let item = player.currentItem else { return }
        var t = player.currentTime().seconds + seconds
        let duration = item.duration.seconds
        if duration.isFinite { t = min(t, duration - 0.1) }
        player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600))
    }

    /// YouTube-style: 0…9 → 0%…90% of the duration.
    func seek(toFraction fraction: Double) {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
        player.seek(to: CMTime(seconds: duration * fraction, preferredTimescale: 600))
    }

    func changeVolume(_ delta: Float) {
        player.volume = min(1, max(0, player.volume + delta))
    }

    func toggleMute() { player.isMuted.toggle() }

    func stepFrame(_ count: Int) {
        player.pause()
        player.currentItem?.step(byCount: count)
    }

    func changeRate(_ delta: Float) {
        let rate = min(4, max(0.25, player.defaultRate + delta))
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    func resetRate() {
        player.defaultRate = 1
        if player.rate != 0 { player.rate = 1 }
    }

    /// PDF or text/hex is showing: ↑/↓/PageUp/PageDown scroll instead of stepping files.
    var isScrollable: Bool { !pdfView.isHidden || (!content.isHidden && content.isShowingText) }

    /// `pages` is a fraction of the visible height (±1 = PageDown/PageUp); otherwise scroll by points.
    func scroll(points: CGFloat = 0, pages: CGFloat = 0) {
        if !pdfView.isHidden, let sv = pdfView.documentView?.enclosingScrollView {
            sv.scrollContent(by: points + pages * sv.contentView.bounds.height * 0.9)
        } else if !content.isHidden {
            content.scrollText(by: points + pages * content.textPageHeight * 0.9)
        }
    }

    /// ⌘+ / ⌘− / ⌘0. `direction` +1 in, -1 out, 0 = fit. PDF: PDFKit zoom; image: centered zoom
    /// (drag to pan, pinch works too); text/hex: preview font size; video: nothing.
    func zoom(_ direction: Int) {
        if !pdfView.isHidden {
            switch direction {
            case 1: pdfView.zoomIn(nil)
            case -1: pdfView.zoomOut(nil)
            default: pdfView.autoScales = true
            }
        } else if !content.isHidden {
            content.zoom(direction)
        }
    }

    /// J/K: page through PDFs, scroll text.
    func seek(lines: Int) {
        if !pdfView.isHidden {
            if lines > 0 { pdfView.goToNextPage(nil) } else { pdfView.goToPreviousPage(nil) }
        } else if !content.isHidden {
            content.seek(lines: lines)
        }
    }
}

/// Keyboard stays with BrowserView; these views are mouse-only so our keymap keeps working.
private final class PassivePlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
}

private final class PassivePDFView: PDFView {
    override var acceptsFirstResponder: Bool { false }
}
