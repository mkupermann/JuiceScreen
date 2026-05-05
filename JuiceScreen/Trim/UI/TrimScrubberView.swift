import SwiftUI

struct TrimScrubberView: View {

    @Bindable var vm: TrimViewModel

    private let trackHeight: CGFloat = 40
    private let handleWidth: CGFloat = 14
    private let trackBackground = Color.secondary.opacity(0.18)
    private let trackSelected = Color.accentColor.opacity(0.35)
    private let handleColor = Color.accentColor

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalSec = max(vm.assetDurationSeconds, 0.001)
            let startX = CGFloat(vm.range.start.seconds / totalSec) * width
            let endX = CGFloat(vm.range.end.seconds / totalSec) * width
            let playheadX = CGFloat(vm.currentTime.seconds / totalSec) * width

            ZStack(alignment: .leading) {
                // Background track (full asset)
                RoundedRectangle(cornerRadius: 8)
                    .fill(trackBackground)
                    .frame(height: trackHeight)

                // Selected sub-range
                RoundedRectangle(cornerRadius: 8)
                    .fill(trackSelected)
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                // Playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: trackHeight)
                    .offset(x: max(0, min(width - 2, playheadX)))
                    .opacity(0.85)

                // Start handle
                handle(x: startX, width: width) { newX in
                    vm.setStart(seconds: Double(newX / width) * totalSec)
                }

                // End handle
                handle(x: endX - handleWidth, width: width) { newX in
                    let edge = newX + handleWidth
                    vm.setEnd(seconds: Double(edge / width) * totalSec)
                }
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }

    @ViewBuilder
    private func handle(x: CGFloat, width: CGFloat, onChanged: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(handleColor)
            .frame(width: handleWidth, height: trackHeight + 12)
            .overlay(
                Rectangle().fill(Color.white).frame(width: 2, height: 16)
            )
            .offset(x: max(0, min(width - handleWidth, x)), y: -6)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let candidate = max(0, min(width - handleWidth, value.location.x - handleWidth / 2))
                        onChanged(candidate)
                    }
            )
    }
}
