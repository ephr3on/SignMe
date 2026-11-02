import SwiftUI
import SwiftData
import PencilKit

/// Settings › Signatures: draw and save signatures, pick the default one for exports.
struct SignaturesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSignature.createdAt) private var signatures: [SavedSignature]
    @AppStorage(AppSettings.Keys.defaultSignatureID) private var defaultSignatureID = AppSettings.Defaults.defaultSignatureID

    @State private var drawing = PKDrawing()
    @State private var name = ""
    @State private var signaturePendingDelete: SavedSignature?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !drawing.strokes.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // The drawing pad sits outside the scroll view so signing never scrolls the page.
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("New signature")
                drawingPad
                TextField("Name (e.g. Full signature)", text: $name)
                    .foregroundStyle(Theme.textPrimary)
                    .card(padding: 14, radius: 14)
                HStack(spacing: 10) {
                    Button("Clear") { drawing = PKDrawing() }
                        .buttonStyle(OutlineButtonStyle(height: 48))
                        .disabled(drawing.strokes.isEmpty)
                    Button("Save signature", action: saveSignature)
                        .buttonStyle(GoldButtonStyle(height: 48))
                        .disabled(!canSave)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Saved")
                    if signatures.isEmpty {
                        Text("No signatures yet. Draw one above and tap Save.")
                            .font(.app(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                            .card(padding: 14, radius: 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(signatures) { signature in
                                signatureRow(signature)
                                if signature.id != signatures.last?.id {
                                    Divider().overlay(Theme.hairline)
                                }
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Toggle(isOn: askEveryTime) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask on every export")
                                .font(.app(.body, .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(defaultSignatureID.isEmpty
                                 ? "You choose a signature each time you export."
                                 : "Off: your default signature is used automatically.")
                                .font(.app(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .disabled(signatures.isEmpty)
                    .card(padding: 14, radius: 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .themedScreen()
        .tabBarSpace()
        .navigationTitle("Signatures")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this signature?",
            isPresented: Binding(
                get: { signaturePendingDelete != nil },
                set: { if !$0 { signaturePendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: signaturePendingDelete
        ) { signature in
            Button("Delete \"\(signature.name)\"", role: .destructive) { delete(signature) }
        }
    }

    private var drawingPad: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.paper)
            Rectangle()
                .fill(Theme.paperLine)
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            Text("Sign above the line with your finger")
                .font(.app(.caption))
                .foregroundStyle(Color(hex: 0x6B6455))
                .padding(.leading, 24)
                .padding(.bottom, 14)
            SignaturePad(drawing: $drawing)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func signatureRow(_ signature: SavedSignature) -> some View {
        let isDefault = signature.id.uuidString == defaultSignatureID
        return HStack(spacing: 12) {
            SignatureThumbnail(signature: signature)
                .frame(width: 96, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(signature.name)
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if isDefault {
                    Text("Default for exports")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
            Spacer()
            Menu {
                if isDefault {
                    Button("Stop Using as Default", systemImage: "star.slash") { defaultSignatureID = "" }
                } else {
                    Button("Use as Default", systemImage: "star") { defaultSignatureID = signature.id.uuidString }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { signaturePendingDelete = signature }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(signature.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// The toggle is "on" while no default is set. Turning it off makes the
    /// first signature the default.
    private var askEveryTime: Binding<Bool> {
        Binding(
            get: { defaultSignatureID.isEmpty },
            set: { ask in
                if ask {
                    defaultSignatureID = ""
                } else if let first = signatures.first {
                    defaultSignatureID = first.id.uuidString
                }
            }
        )
    }

    private func saveSignature() {
        guard let data = SignaturePad.pngData(from: drawing) else { return }
        let label = trimmedName.isEmpty ? "Signature \(signatures.count + 1)" : trimmedName
        let signature = SavedSignature(name: label, imageData: data)
        modelContext.insert(signature)
        drawing = PKDrawing()
        name = ""
    }

    private func delete(_ signature: SavedSignature) {
        if signature.id.uuidString == defaultSignatureID {
            defaultSignatureID = ""
        }
        modelContext.delete(signature)
    }
}

/// A saved signature on a small paper swatch.
struct SignatureThumbnail: View {
    let signature: SavedSignature?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.paper)
            .overlay {
                if let image = signature?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Text("None")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(Color(hex: 0x6B6455))
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        SignaturesView()
    }
    .modelContainer(PreviewSupport.container)
    .preferredColorScheme(.dark)
}
