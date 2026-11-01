import SwiftUI

/// A single reusable "enter a name" sheet, used for adding/renaming both
/// Jobs and Projects so that logic isn't duplicated across those screens.
struct NameEntrySheet: View {
    let title: String
    var fieldLabel: String = "Name"
    var initialValue: String = ""
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(title: String, fieldLabel: String = "Name", initialValue: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.initialValue = initialValue
        self.onSave = onSave
        _name = State(initialValue: initialValue)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(fieldLabel, text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
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
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.height(180)])
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
        dismiss()
    }
}

#Preview {
    NameEntrySheet(title: "New Job", fieldLabel: "Job Name") { _ in }
}
