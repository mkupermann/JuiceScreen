import SwiftUI

struct TrimEditorView: View {
    @Bindable var vm: TrimViewModel
    let onSaveTrim: () -> Void
    let onSaveTrimAs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerView(player: vm.player)
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 6) {
                TrimScrubberView(vm: vm)
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                if let message = vm.trimErrorMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.red)
                        .padding(.horizontal, 14)
                }
                if vm.isExporting {
                    ProgressView().progressViewStyle(.linear).padding(.horizontal, 14)
                }
                TrimToolbarView(vm: vm, onSaveTrim: onSaveTrim, onSaveTrimAs: onSaveTrimAs)
            }
            .background(.regularMaterial)
        }
    }
}
