import SwiftUI
import UIKit

/// A file that has just been generated for sharing. `url` is nil when the
/// export failed, which shows an error alert instead of the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL?

    init(_ url: URL?) {
        self.url = url
    }
}

/// Wraps `UIActivityViewController` so exports can be generated on tap and
/// then shared, instead of being built on every SwiftUI render like `ShareLink` requires.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareSheetModifier: ViewModifier {
    @Binding var item: ShareItem?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { item?.url == nil ? nil : item },
                set: { item = $0 }
            )) { shareItem in
                if let url = shareItem.url {
                    ShareSheet(url: url) { item = nil }
                        .presentationDetents([.medium, .large])
                        .ignoresSafeArea()
                }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { item != nil && item?.url == nil },
                set: { if !$0 { item = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text("SignMe couldn't create the export file. Please try again.")
            }
    }
}

extension View {
    /// Shows the system share sheet for `item` (or an error alert if its file
    /// couldn't be created). Set `item` from a button action, e.g.
    /// `shareItem = ShareItem(ExportService.backupExportURL(jobs: jobs))`.
    func shareSheet(item: Binding<ShareItem?>) -> some View {
        modifier(ShareSheetModifier(item: item))
    }
}
