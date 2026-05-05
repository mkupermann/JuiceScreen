import AVFoundation
import AppKit
import SwiftUI

/// Hosts an `AVPlayerLayer` in a SwiftUI view.
struct AVPlayerView: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        nsView.player = player
    }
}

/// AppKit-backed view that owns an `AVPlayerLayer`. Auto-resizes the layer with the view.
final class PlayerHostView: NSView {

    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
