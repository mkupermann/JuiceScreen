import AVFoundation
import AppKit
import SwiftUI

@MainActor
final class TrimEditorWindow {

    let window: NSWindow
    private let vm: TrimViewModel
    private let trimmer: TrimmerService
    private let captureRecord: CaptureRow
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?
    private let log = AppLog.logger(category: "TrimEditorWindow")

    init(captureRecord: CaptureRow, trimmer: TrimmerService, onClose: @escaping () -> Void) async throws {
        self.captureRecord = captureRecord
        self.trimmer = trimmer
        self.onClose = onClose

        let url = URL(fileURLWithPath: captureRecord.filePath)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        let vm = TrimViewModel(player: player, sourceURL: url, assetDuration: duration)
        self.vm = vm

        let frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Trim — \(url.lastPathComponent)"
        win.minSize = NSSize(width: 700, height: 480)
        win.center()
        win.isReleasedWhenClosed = false

        self.window = win

        let onSaveTrim: () -> Void = { [weak self] in
            self?.performTrim(saveAs: false)
        }
        let onSaveTrimAs: () -> Void = { [weak self] in
            self?.performTrim(saveAs: true)
        }

        win.contentView = NSHostingView(
            rootView: TrimEditorView(vm: vm, onSaveTrim: onSaveTrim, onSaveTrimAs: onSaveTrimAs)
        )

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { _ in
            onClose()
        }
        self.closeObserver = observer
    }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performTrim(saveAs: Bool) {
        guard vm.range.isValid, !vm.isExporting else { return }
        Task { @MainActor in
            var destination: URL
            if saveAs {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mpeg4Movie]
                panel.nameFieldStringValue = vm.sourceURL.deletingPathExtension().lastPathComponent + "-trimmed"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            } else {
                destination = vm.sourceURL
                    .deletingPathExtension()
                    .appendingPathExtension("trimmed.mp4")
                let parent = destination.deletingLastPathComponent()
                let baseName = destination.deletingPathExtension().lastPathComponent
                var candidate = destination
                var n = 1
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = parent.appendingPathComponent("\(baseName)-\(n).mp4")
                    n += 1
                }
                destination = candidate
            }

            vm.isExporting = true
            vm.trimErrorMessage = nil
            do {
                let written = try await trimmer.trim(
                    sourceURL: vm.sourceURL,
                    range: vm.range,
                    destinationURL: destination
                )
                vm.isExporting = false
                log.info("Trim wrote → \(written.path)")
                NSWorkspace.shared.activateFileViewerSelecting([written])
            } catch {
                vm.isExporting = false
                vm.trimErrorMessage = "Trim failed: \(String(describing: error))"
                log.error("Trim failed: \(String(describing: error))")
            }
        }
    }
}
