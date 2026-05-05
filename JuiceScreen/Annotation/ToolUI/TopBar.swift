import SwiftUI

/// Renders only the controls that apply to the current tool. For `.select`, it shows
/// controls for the selected layer's properties (color/thickness if shape; font if text).
struct TopBar: View {

    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 14) {
            switch state.currentTool {
            case .select:
                if let id = state.selectedLayerID, let layer = state.document.layer(id: id) {
                    selectionControls(for: layer)
                } else {
                    Text("Click an annotation to edit it. Press a tool below to add a new one.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

            case .arrow, .doubleArrow, .line:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)

            case .rectangle, .ellipse:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)
                Toggle("Filled", isOn: $state.currentFilled).toggleStyle(.switch).labelsHidden()
                Text(state.currentFilled ? "Fill" : "Outline")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

            case .pen, .highlighter:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)

            case .text:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                FontControls(fontName: $state.currentFontName, fontSize: $state.currentFontSize)

            case .blur:
                Picker("Style", selection: $state.currentBlurStyle) {
                    Text("Blur").tag(BlurProps.Style.gaussian)
                    Text("Pixelate").tag(BlurProps.Style.pixelate)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Divider().frame(height: 18)
                Slider(value: $state.currentBlurIntensity, in: 4...32, step: 1).frame(width: 120)
                Text("\(Int(state.currentBlurIntensity))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

            case .crop:
                Text("Drag a rectangle to crop. Drag again to update; clear by selecting another tool then re-selecting Crop.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func selectionControls(for layer: AnnotationLayer) -> some View {
        switch layer {
        case .arrow, .line, .freehand:
            Text("Color/thickness apply to the next stroke. Edit via re-creating for v0.3.0.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .rectangle, .ellipse:
            Text("Filled / outlined toggle applies to the next shape.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .text(let p, _):
            Text("\"\(p.text)\" • \(p.fontName) \(Int(p.fontSize))pt")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .blur(let p, _):
            Text("\(p.style == .gaussian ? "Blur" : "Pixelate") • intensity \(Int(p.intensity))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
