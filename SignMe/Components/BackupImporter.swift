import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Shared "Import Backup" flow — the file picker, the merge, and the result
/// alerts — so the Jobs tab and Settings don't each carry their own copy.
private struct BackupImporterModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    @Binding var isPresented: Bool
    let existingJobs: [Job]

    @State private var summaryMessage: String?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json], onCompletion: handleImport)
            .alert("Import Complete", isPresented: Binding(
                get: { summaryMessage != nil },
                set: { if !$0 { summaryMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(summaryMessage ?? "")
            }
            .alert("Import Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try BackupService.importData(data, into: modelContext, existingJobs: existingJobs)
                summaryMessage = summary.message
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// Presents the JSON backup picker when `isPresented` becomes true and merges
    /// the chosen file into `existingJobs`, reporting the result in an alert.
    func backupImporter(isPresented: Binding<Bool>, existingJobs: [Job]) -> some View {
        modifier(BackupImporterModifier(isPresented: isPresented, existingJobs: existingJobs))
    }
}
