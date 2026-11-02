import SwiftUI
import UIKit

/// One or more files that have just been generated for sharing. Empty `urls`
/// means the export failed, which shows an error alert instead of the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]

    init(_ url: URL?) {
        self.urls = url.map { [$0] } ?? []
    }

    init(urls: [URL]?) {
        self.urls = urls ?? []
    }

    var url: URL? { urls.first }
    var didFail: Bool { urls.isEmpty }
}

/// Wraps `UIActivityViewController` so exports can be generated on tap and
/// then shared, instead of being built on every SwiftUI render like `ShareLink` requires.
/// Several files are shared together (e.g. attached to one email or saved to Files at once).
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
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
                get: { (item?.didFail ?? true) ? nil : item },
                set: { item = $0 }
            )) { shareItem in
                ShareSheet(urls: shareItem.urls) { item = nil }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert("Export Failed", isPresented: Binding(
                get: { item?.didFail ?? false },
                set: { if !$0 { item = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text("SignMe couldn't create the export file. Please try again.")
            }
    }
}

extension View {
    /// Shows the system share sheet for `item` (or an error alert if its files
    /// couldn't be created). Set `item` from a button action, e.g.
    /// `shareItem = ShareItem(ExportService.backupExportURL(jobs: jobs))`.
    func shareSheet(item: Binding<ShareItem?>) -> some View {
        modifier(ShareSheetModifier(item: item))
    }
}
