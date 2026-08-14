import SwiftUI

/// Editor-only backdrop that makes transparency visible.
///
/// Deliberately NOT part of `AnnotationCanvas`: that view is also what
/// `AnnotationRenderer` rasterises for export, and the pattern must never end
/// up in an exported file.
struct CheckerboardBackground: View {

    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 1.0)))
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            guard cols > 0, rows > 0 else { return }
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 1 {
                    let square = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    ctx.fill(Path(square), with: .color(Color(white: 0.86)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
