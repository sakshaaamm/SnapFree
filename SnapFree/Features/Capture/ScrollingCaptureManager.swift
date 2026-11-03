//
//  ScrollingCaptureManager.swift
//  SnapFree
//
//  Scrolling (long) capture: records a region while the user scrolls, then
//  stitches the frames into one tall image by detecting vertical overlap.
//

import AppKit
import ScreenCaptureKit
import CoreImage

@MainActor
final class ScrollingCaptureManager: ObservableObject {
    
    static let shared = ScrollingCaptureManager()
    private init() {}
    
    @Published var isCapturing = false
    
    private var region: CGRect = .zero          // screen-local points, top-left origin
    private var display: SCDisplay?
    private var scale: CGFloat = 2
    private var captureTimer: Timer?
    private var frames: [CGImage] = []
    private var controlWindow: NSWindow?
    private var onFinished: ((NSImage) -> Void)?
    
    // MARK: - Public entry
    
    /// Start a scrolling capture. The user selects a region, scrolls through
    /// the content, then presses Done. The stitched image is returned via
    /// `completion`.
    func start(completion: @escaping (NSImage) -> Void) {
        self.onFinished = completion
        
        // Show the instructions every time Scrolling Capture starts.
        let alert = NSAlert()
        alert.messageText = "Scrolling Capture — How it works"
        alert.informativeText = """
        1. Drag to select the area to capture (e.g. a web page's content column).
        2. A control appears at the top of the screen.
        3. Scroll DOWN slowly and steadily through the whole content.
        4. Click Done — SnapFree stitches it into one tall screenshot.

        Tip: scroll smoothly in small steps. Overlapping views stitch best.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            return   // user cancelled
        }
        
        Task {
            do {
                let rect = try await SelectionOverlayManager.shared.requestAreaSelection()
                try await DisplayManager.shared.refreshContent()
                guard let disp = DisplayManager.shared.displayAtMouseLocation()
                        ?? DisplayManager.shared.mainDisplay else { return }
                
                self.region = rect
                self.display = disp
                self.scale = NSScreen.main?.backingScaleFactor ?? 2
                self.frames = []
                self.isCapturing = true
                
                self.showControlWindow()
                self.beginTimedCapture()
            } catch {
                // User cancelled the selection.
                self.isCapturing = false
            }
        }
    }
    
    // MARK: - Timed capture
    
    private func beginTimedCapture() {
        // Capture ~12 frames/second. A dense frame stream gives the stitcher many
        // candidates to choose from, so it can almost always find a frame whose
        // scroll delta lands on a clean pixel-row boundary — the key to invisible
        // seams. Cost is paid once at stitch time, not during capture.
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.captureOneFrame()
            }
        }
    }
    
    private func captureOneFrame() async {
        // Stop if capture was cancelled/finished between timer fire and now.
        guard isCapturing, let display = display else { return }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        
        do {
            let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // Crop to the selected region (pixels, top-left origin).
            let pixelRect = CGRect(
                x: region.origin.x * scale,
                y: region.origin.y * scale,
                width: region.width * scale,
                height: region.height * scale
            ).integral
            if let cropped = full.cropping(to: pixelRect) {
                // Skip near-duplicate frames (user not scrolling).
                if let last = frames.last, imagesAreSimilar(last, cropped) {
                    return
                }
                frames.append(cropped)
                updateStatus()
            }
        } catch {
            // Ignore a single failed frame.
        }
    }
    
    // MARK: - Control window
    
    private weak var statusLabel: NSTextField?
    
    private func showControlWindow() {
        let width: CGFloat = 300
        let height: CGFloat = 120
        let window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver   // above the content being scrolled
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = 14
        
        // Title
        let title = NSTextField(labelWithString: "📜  Scrolling Capture")
        title.frame = NSRect(x: 16, y: height - 32, width: width - 32, height: 20)
        title.textColor = .white
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        container.addSubview(title)
        
        // Instructions / live status
        let status = NSTextField(wrappingLabelWithString:
            "Scroll DOWN slowly through the content.\nClick Done when you reach the end.")
        status.frame = NSRect(x: 16, y: 40, width: width - 32, height: 36)
        status.textColor = NSColor.white.withAlphaComponent(0.85)
        status.font = .systemFont(ofSize: 11)
        status.maximumNumberOfLines = 2
        container.addSubview(status)
        statusLabel = status
        
        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.frame = NSRect(x: 16, y: 10, width: 130, height: 26)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"   // Return = Done
        container.addSubview(doneButton)
        
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 154, y: 10, width: 130, height: 26)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"  // Esc = Cancel
        container.addSubview(cancelButton)
        
        window.contentView = container
        
        if let screen = NSScreen.main {
            // Top-center so it doesn't block the content being scrolled.
            window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.maxY - height - 20
            ))
        }
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }
    
    private func updateStatus() {
        statusLabel?.stringValue = "Captured \(frames.count) frame\(frames.count == 1 ? "" : "s"). Keep scrolling…\nClick Done when you reach the end."
    }
    
    @objc private func finish() {
        isCapturing = false
        stopCapture()
        
        guard !frames.isEmpty else { return }
        
        let stitched = stitchFrames(frames)
        let completion = onFinished
        onFinished = nil
        frames = []
        completion?(stitched)
    }
    
    @objc private func cancel() {
        isCapturing = false      // set first so any in-flight frame bails out
        stopCapture()
        frames = []
        onFinished = nil
    }
    
    private func stopCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        controlWindow?.orderOut(nil)
        controlWindow?.contentView = nil
        controlWindow = nil
    }
    
    // MARK: - Stitching
    
    /// Stitch frames vertically. For each consecutive frame, find how much the
    /// content shifted DOWN by matching the BOTTOM of the previous frame against
    /// the TOP of the current frame. Append only the non-overlapping new rows.
    private func stitchFrames(_ frames: [CGImage]) -> NSImage {
        guard let first = frames.first else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        guard frames.count > 1 else {
            return NSImage(cgImage: first,
                           size: NSSize(width: region.width, height: region.height))
        }
        
        let width = first.width
        var pieces: [CGImage] = [first]
        var totalHeight = first.height
        
        // We want each seam to be PIXEL-EXACT so no text line is sliced. Rather
        // than appending the first frame that overlaps the reference, we look at
        // a window of upcoming candidate frames and pick the one that both
        // advances the content the most AND aligns almost perfectly (lowest
        // match error). This yields invisible seams even when the user scrolls
        // unevenly, because there is almost always one frame in the window whose
        // scroll delta happens to land on a clean row boundary.
        let errorThreshold = 6.0            // max acceptable seam error
        var reference = first
        var i = 1
        while i < frames.count {
            // Evaluate a lookahead window of candidates against the reference.
            let windowEnd = min(frames.count, i + 10)
            var bestIdx = -1
            var bestOverlap = 0
            var bestError = Double.greatestFiniteMagnitude
            var bestNewHeight = 0
            
            for j in i..<windowEnd {
                let cand = frames[j]
                let (overlap, error) = findOverlap(prevBottom: reference, currTop: cand)
                guard overlap > 0 else { continue }
                let newHeight = cand.height - overlap
                guard newHeight > 0 else { continue }
                
                // Prefer the lowest-error (most seamless) candidate. Among
                // near-equal errors, prefer the one that advances more content so
                // we don't crawl frame by frame.
                let better = error < bestError - 0.5
                    || (abs(error - bestError) <= 0.5 && newHeight > bestNewHeight)
                if error <= errorThreshold && better {
                    bestError = error
                    bestOverlap = overlap
                    bestNewHeight = newHeight
                    bestIdx = j
                }
            }
            
            if bestIdx >= 0 {
                let chosen = frames[bestIdx]
                // findOverlap is top-left origin: the top `overlap` rows of the
                // chosen frame duplicate the reference; the NEW content is the
                // bottom rows (overlap..<height). CGImage.cropping is also
                // top-left origin, so crop starting at y = overlap.
                if let newPart = chosen.cropping(to: CGRect(
                    x: 0, y: bestOverlap, width: chosen.width, height: bestNewHeight
                )) {
                    pieces.append(newPart)
                    totalHeight += bestNewHeight
                    reference = chosen
                }
                i = bestIdx + 1          // continue after the chosen frame
            } else {
                // No seamless candidate in this window. Advance past it and keep
                // the same reference so later frames can still align.
                i = windowEnd
            }
        }
        
        // Compose the tall image.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: first, size: NSSize(width: region.width, height: region.height))
        }
        
        var y = totalHeight
        for piece in pieces {
            y -= piece.height
            ctx.draw(piece, in: CGRect(x: 0, y: y, width: piece.width, height: piece.height))
        }
        
        guard let out = ctx.makeImage() else {
            return NSImage(cgImage: first, size: NSSize(width: region.width, height: region.height))
        }
        
        let pointHeight = CGFloat(totalHeight) / scale
        return NSImage(cgImage: out, size: NSSize(width: region.width, height: pointHeight))
    }
    
    /// Find how many pixel rows at the TOP of `curr` overlap the BOTTOM of `prev`
    /// (i.e. content the two frames share, for a user scrolling DOWN).
    ///
    /// For a seamless join the overlap must be found to the EXACT pixel row, so
    /// the cut lands on a real content boundary rather than slicing through a
    /// line of text. We do a coarse-to-fine search:
    ///   1. Coarse: slide a bottom anchor strip of `prev` over `curr` using
    ///      sparse sampling to locate the approximate scroll shift cheaply.
    ///   2. Fine: around that estimate, re-score every candidate shift using
    ///      DENSE sampling (every row, many columns) to lock onto the exact
    ///      pixel offset.
    /// We only accept a match that is nearly perfect; otherwise we return 0 so
    /// the frame is skipped instead of producing a misregistered seam.
    ///
    /// All indexing is top-left origin (row 0 = top), matching `pixelData`.
    /// Returns the overlap row count and the match error (lower = better; a value
    /// near 0 means a pixel-exact seam). A caller can use the error to choose the
    /// best of several candidate frames.
    private func findOverlap(prevBottom prev: CGImage, currTop curr: CGImage) -> (overlap: Int, error: Double) {
        let h = min(prev.height, curr.height)
        guard h > 40 else { return (0, .greatestFiniteMagnitude) }
        guard let prevPixels = pixelData(for: prev),
              let currPixels = pixelData(for: curr) else { return (0, .greatestFiniteMagnitude) }
        
        let prevH = prev.height
        let currH = curr.height
        let w = prev.width
        
        // Anchor: a strip just above the bottom edge of prev.
        let anchorHeight = max(24, h / 6)
        let anchorTopInPrev = prevH - anchorHeight
        guard anchorTopInPrev >= 0 else { return (0, .greatestFiniteMagnitude) }
        let maxShift = anchorTopInPrev
        guard maxShift >= 1 else { return (0, .greatestFiniteMagnitude) }
        
        // Scores the anchor against curr at a given shift.
        // `rowStep`/`colStep` control density; smaller = more precise, slower.
        func score(shift: Int, rowStep: Int, colStep: Int) -> Double {
            let currStart = anchorTopInPrev - shift
            if currStart < 0 { return .greatestFiniteMagnitude }
            var diff: Double = 0
            var samples: Double = 0
            var k = 0
            while k < anchorHeight {
                let prevRow = anchorTopInPrev + k
                let currRow = currStart + k
                if prevRow < prevH && currRow < currH {
                    let prevBase = prevRow * w
                    let currBase = currRow * w
                    var col = 0
                    while col < w {
                        let pIdx = (prevBase + col) * 4
                        let cIdx = (currBase + col) * 4
                        if pIdx + 2 < prevPixels.count && cIdx + 2 < currPixels.count {
                            diff += abs(Double(prevPixels[pIdx])     - Double(currPixels[cIdx]))
                            diff += abs(Double(prevPixels[pIdx + 1]) - Double(currPixels[cIdx + 1]))
                            diff += abs(Double(prevPixels[pIdx + 2]) - Double(currPixels[cIdx + 2]))
                            samples += 3.0
                        }
                        col += colStep
                    }
                }
                k += rowStep
            }
            return samples > 0 ? diff / samples : .greatestFiniteMagnitude
        }
        
        // --- Stage 1: coarse search over all shifts (sparse). ---
        let coarseRowStep = 3
        let coarseColStep = max(1, w / 48)
        var coarseBest = -1
        var coarseBestScore = Double.greatestFiniteMagnitude
        var shift = 1
        while shift <= maxShift {
            let s = score(shift: shift, rowStep: coarseRowStep, colStep: coarseColStep)
            if s < coarseBestScore {
                coarseBestScore = s
                coarseBest = shift
            }
            shift += 1
        }
        guard coarseBest > 0 else { return (0, .greatestFiniteMagnitude) }
        
        // --- Stage 2: fine search in a small window around the coarse estimate,
        // using DENSE sampling (every row, many columns) for pixel accuracy. ---
        let fineColStep = max(1, w / 256)   // dense columns
        let window = 6
        let lo = max(1, coarseBest - window)
        let hi = min(maxShift, coarseBest + window)
        var bestShift = -1
        var bestScore = Double.greatestFiniteMagnitude
        var secondBestScore = Double.greatestFiniteMagnitude
        var s2 = lo
        while s2 <= hi {
            let sc = score(shift: s2, rowStep: 1, colStep: fineColStep)
            if sc < bestScore {
                secondBestScore = bestScore
                bestScore = sc
                bestShift = s2
            } else if sc < secondBestScore {
                secondBestScore = sc
            }
            s2 += 1
        }
        guard bestShift > 0 else { return (0, .greatestFiniteMagnitude) }
        
        let overlap = prevH - bestShift
        if overlap <= 0 { return (0, .greatestFiniteMagnitude) }
        if overlap >= currH { return (currH - 1, bestScore) }
        return (overlap, bestScore)
    }
    
    /// Extract raw RGBA pixel data from a CGImage (top-left origin).
    private func pixelData(for image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * h)
        
        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }
    
    /// Quick check if two frames are near-identical (user not scrolling).
    private func imagesAreSimilar(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let pa = pixelData(for: a), let pb = pixelData(for: b) else { return false }
        
        let step = max(1, pa.count / 400)  // sample ~400 pixels
        var diff: Double = 0
        var n: Double = 0
        var i = 0
        while i < pa.count {
            diff += abs(Double(pa[i]) - Double(pb[i]))
            n += 1
            i += step
        }
        return n > 0 && (diff / n) < 4.0
    }
}

// MARK: - Keyable Panel

/// A borderless panel that can still become key so its buttons receive clicks.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
