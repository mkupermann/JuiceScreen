import SwiftUI

/// Renders only the controls that apply to the current tool. For `.select`, it shows
/// editable controls for the selected layer's properties — color, thickness, fill, text —
/// and writes back via `state.replace(...)` so changes apply in place.
struct TopBar: View {

    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 14) {
            switch state.currentTool {
            case .select:
                if let id = state.selectedLayerID, let layer = state.document.layer(id: id) {
                    selectionControls(for: layer)
                } else {
                    Text("Select a layer to edit.")
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
                Toggle("Filled", isOn: $state.currentFilled)
                    .toggleStyle(.switch)

            case .pen, .highlighter:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)

            case .text:
                TextField("Type, then press Return or click to place", text: $state.currentText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240, idealWidth: 320)
                    .onSubmit { state.placeTextAtCanvasCenter() }
                Divider().frame(height: 18)
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
                Text("Drag to set crop region. Press Esc or pick another tool to clear.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.bar)
    }

    // MARK: - Selection controls — bound to the selected layer for in-place editing

    @ViewBuilder
    private func selectionControls(for layer: AnnotationLayer) -> some View {
        switch layer {
        case .arrow(let p, let id):
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.arrow(ArrowProps(start: p.start, end: p.end, color: c, thickness: p.thickness, doubleHeaded: p.doubleHeaded), id: id)) }
            ))
            Divider().frame(height: 18)
            ThicknessSlider(thickness: binding(
                get: { p.thickness },
                set: { t in state.replace(.arrow(ArrowProps(start: p.start, end: p.end, color: p.color, thickness: t, doubleHeaded: p.doubleHeaded), id: id)) }
            ))

        case .line(let p, let id):
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.line(LineProps(start: p.start, end: p.end, color: c, thickness: p.thickness), id: id)) }
            ))
            Divider().frame(height: 18)
            ThicknessSlider(thickness: binding(
                get: { p.thickness },
                set: { t in state.replace(.line(LineProps(start: p.start, end: p.end, color: p.color, thickness: t), id: id)) }
            ))

        case .rectangle(let p, let id):
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.rectangle(ShapeProps(rect: p.rect, color: c, thickness: p.thickness, filled: p.filled), id: id)) }
            ))
            Divider().frame(height: 18)
            ThicknessSlider(thickness: binding(
                get: { p.thickness },
                set: { t in state.replace(.rectangle(ShapeProps(rect: p.rect, color: p.color, thickness: t, filled: p.filled), id: id)) }
            ))
            Toggle("Filled", isOn: binding(
                get: { p.filled },
                set: { f in state.replace(.rectangle(ShapeProps(rect: p.rect, color: p.color, thickness: p.thickness, filled: f), id: id)) }
            ))
            .toggleStyle(.switch)

        case .ellipse(let p, let id):
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.ellipse(ShapeProps(rect: p.rect, color: c, thickness: p.thickness, filled: p.filled), id: id)) }
            ))
            Divider().frame(height: 18)
            ThicknessSlider(thickness: binding(
                get: { p.thickness },
                set: { t in state.replace(.ellipse(ShapeProps(rect: p.rect, color: p.color, thickness: t, filled: p.filled), id: id)) }
            ))
            Toggle("Filled", isOn: binding(
                get: { p.filled },
                set: { f in state.replace(.ellipse(ShapeProps(rect: p.rect, color: p.color, thickness: p.thickness, filled: f), id: id)) }
            ))
            .toggleStyle(.switch)

        case .freehand(let p, let id):
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.freehand(FreehandProps(points: p.points, color: c, thickness: p.thickness, isHighlighter: p.isHighlighter), id: id)) }
            ))
            Divider().frame(height: 18)
            ThicknessSlider(thickness: binding(
                get: { p.thickness },
                set: { t in state.replace(.freehand(FreehandProps(points: p.points, color: p.color, thickness: t, isHighlighter: p.isHighlighter), id: id)) }
            ))

        case .text(let p, let id):
            TextField("Text", text: binding(
                get: { p.text },
                set: { newText in state.replace(.text(TextProps(origin: p.origin, text: newText, color: p.color, fontName: p.fontName, fontSize: p.fontSize), id: id)) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 200, idealWidth: 260)
            Divider().frame(height: 18)
            ColorSwatchPicker(color: binding(
                get: { p.color },
                set: { c in state.replace(.text(TextProps(origin: p.origin, text: p.text, color: c, fontName: p.fontName, fontSize: p.fontSize), id: id)) }
            ))
            Divider().frame(height: 18)
            FontControls(
                fontName: binding(
                    get: { p.fontName },
                    set: { f in state.replace(.text(TextProps(origin: p.origin, text: p.text, color: p.color, fontName: f, fontSize: p.fontSize), id: id)) }
                ),
                fontSize: binding(
                    get: { p.fontSize },
                    set: { s in state.replace(.text(TextProps(origin: p.origin, text: p.text, color: p.color, fontName: p.fontName, fontSize: s), id: id)) }
                )
            )

        case .blur(let p, let id):
            Picker("Style", selection: binding(
                get: { p.style },
                set: { s in state.replace(.blur(BlurProps(rect: p.rect, style: s, intensity: p.intensity), id: id)) }
            )) {
                Text("Blur").tag(BlurProps.Style.gaussian)
                Text("Pixelate").tag(BlurProps.Style.pixelate)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            Divider().frame(height: 18)
            Slider(value: binding(
                get: { p.intensity },
                set: { i in state.replace(.blur(BlurProps(rect: p.rect, style: p.style, intensity: i), id: id)) }
            ), in: 4...32, step: 1)
            .frame(width: 120)
            Text("\(Int(p.intensity))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// Helper that wraps two closures into a SwiftUI Binding.
    private func binding<T>(get: @escaping () -> T, set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}
