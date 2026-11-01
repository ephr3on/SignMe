import SwiftUI

/// A single reusable "enter a name" sheet, used for adding/renaming both
/// Jobs and Projects so that logic isn't duplicated across those screens.
/// Names already in `existingNames` (compared trimmed and case-insensitively)
/// are rejected, so two jobs — or two projects in one job — can't share a name.
struct NameEntrySheet: View {
    let title: String
    var fieldLabel: String = "Name"
    var initialValue: String = ""
    var existingNames: [String] = []
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(
        title: String,
        fieldLabel: String = "Name",
        initialValue: String = "",
        existingNames: [String] = [],
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.initialValue = initialValue
        self.existingNames = existingNames
        self.onSave = onSave
        _name = State(initialValue: initialValue)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if the name is taken by *another* item. Keeping an item's own name
    /// (or only changing its capitalization) while renaming is allowed.
    private var isDuplicate: Bool {
        let key = trimmedName.normalizedNameKey
        guard !key.isEmpty, key != initialValue.normalizedNameKey else { return false }
        return existingNames.contains { $0.normalizedNameKey == key }
    }

    private var canSave: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(fieldLabel, text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    if isDuplicate {
                        Text("That name is already in use. Choose a different one.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.height(200)])
    }

    private func save() {
        guard canSave else { return }
        onSave(trimmedName)
        dismiss()
    }
}

#Preview {
    NameEntrySheet(title: "New Job", fieldLabel: "Job Name", existingNames: ["Acme Studio"]) { _ in }
}
