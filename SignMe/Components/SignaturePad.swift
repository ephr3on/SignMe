import SwiftUI
import PencilKit
import UIKit

/// A finger-friendly drawing area for signatures (PencilKit), always drawn as
/// dark-blue ink on paper regardless of dark mode.
struct SignaturePad: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: Theme.inkUIColor, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light   // keep ink dark blue in dark mode
        canvas.isScrollEnabled = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = "Signature drawing area"
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Only push changes that came from outside (e.g. the Clear button).
        if drawing.strokes.isEmpty && !canvas.drawing.strokes.isEmpty {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }

    /// Renders the strokes as a tightly-cropped, transparent PNG at 3× scale.
    static func pngData(from drawing: PKDrawing) -> Data? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        return image?.pngData()
    }
}
