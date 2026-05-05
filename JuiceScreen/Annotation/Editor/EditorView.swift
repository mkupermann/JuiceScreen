import SwiftUI

struct EditorView: View {
    @Bindable var state: EditorState
    let actions: QuickActions

    var body: some View {
        HStack(spacing: 0) {
            ToolPalette(state: state)
            VStack(spacing: 0) {
                TopBar(state: state)
                ZStack(alignment: .topLeading) {
                    AnnotationCanvas(baseImage: state.document.baseImage,
                                     layers: state.document.layers,
                                     canvasSize: canvasPointSize)
                    if let id = state.selectedLayerID, let layer = state.document.layer(id: id) {
                        SelectionHandlesView(layer: layer)
                            .frame(width: canvasPointSize.width, height: canvasPointSize.height, alignment: .topLeading)
                    }
                    CanvasGestures(state: state)
                        .frame(width: canvasPointSize.width, height: canvasPointSize.height)
                }
                .frame(width: canvasPointSize.width, height: canvasPointSize.height)
                .clipped()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { actions.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: .command).help("Copy to clipboard (⌘C)")
                Button { actions.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command).help("Save (⌘S)")
                Button { actions.saveAs() } label: { Label("Save As…", systemImage: "square.and.arrow.down.on.square") }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).help("Save As… (⌘⇧S)")
                Button { actions.showInFinder() } label: { Label("Reveal", systemImage: "folder") }
                    .help("Show in Finder")
            }
        }
        .editorKeyboardCommands(state: state)
    }

    private var canvasPointSize: CGSize {
        let pixelW = CGFloat(state.captureRecord.pixelWidth)
        let pixelH = CGFloat(state.captureRecord.pixelHeight)
        return CGSize(width: pixelW / 2, height: pixelH / 2)
    }
}
