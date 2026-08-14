import SwiftUI

/// One overlay's interactive surface for freeform selection.
///
/// Same `GeometryReader` discipline as `RegionPickerView`: gesture space and
/// render space must be the same `proxy.size` rect, or safe-area insets shift
/// the drawn path away from where the gesture thinks it is.
struct FreeformPickerView: View {

    let canvasSize: CGSize
    let isActive: Bool
    let onBegan: () -> Void
    let onCommitted: (FreeformSelection?) -> Void

    @State private var selection = FreeformSelection(mode: .freehand)
    @State private var cursor: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.35)
                    .mask(dimMask)

                Path(selection.closedPath)
                    .stroke(Color.white, lineWidth: 1)
                    .allowsHitTesting(false)

                if selection.mode == .polygon, let cursor, let last = selection.points.last {
                    Path { p in
                        p.move(to: last)
                        p.addLine(to: cursor)
                    }
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false)
                }

                if let cursor, selection.isUsable {
                    Text("\(Int(selection.bounds.width)) × \(Int(selection.bounds.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: cursor.x + 16, y: cursor.y + 16)
                        .allowsHitTesting(false)
                }

                hud
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(freehandGesture)
            .onTapGesture(count: 2) { closeIfPossible() }
            .simultaneousGesture(polygonTap)
            .onContinuousHover { phase in
                if case .active(let point) = phase { cursor = point } else { cursor = nil }
            }
        }
        .ignoresSafeArea()
        // focusable() is required — onKeyPress only fires for a focused view, and
        // without it Tab / Return / Backspace silently do nothing in the overlay.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.tab) { toggleMode(); return .handled }
        .onKeyPress(.return) { closeIfPossible(); return .handled }
        .onKeyPress(.delete) { selection.removeLastVertex(); return .handled }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var dimMask: some View {
        if selection.points.count >= 3 {
            Rectangle()
                .overlay(Path(selection.closedPath).fill(Color.black).blendMode(.destinationOut))
                .compositingGroup()
        } else {
            Rectangle()
        }
    }

    private var hud: some View {
        VStack {
            Spacer()
            Text(selection.mode == .freehand
                 ? "Freehand · Tab for polygon · Esc cancels"
                 : "Polygon · click to add · ⏎ or double-click to close · ⌫ undo · Esc cancels")
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 24)
                .allowsHitTesting(false)
        }
    }

    private var freehandGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard selection.mode == .freehand else { return }
                if selection.points.isEmpty { onBegan() }
                guard isActive else { return }
                selection.append(value.location)
                cursor = value.location
            }
            .onEnded { _ in
                guard selection.mode == .freehand, isActive else { return }
                commit()
            }
    }

    private var polygonTap: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { value in
                guard selection.mode == .polygon else { return }
                if selection.points.isEmpty { onBegan() }
                guard isActive else { return }
                selection.appendVertex(value.location)
            }
    }

    // MARK: - Actions

    private func toggleMode() {
        selection.setMode(selection.mode == .freehand ? .polygon : .freehand)
    }

    private func closeIfPossible() {
        guard selection.mode == .polygon, isActive else { return }
        commit()
    }

    private func commit() {
        if selection.isUsable {
            onCommitted(selection)
        } else {
            onCommitted(nil)
        }
        selection = FreeformSelection(mode: selection.mode)
        cursor = nil
    }
}
