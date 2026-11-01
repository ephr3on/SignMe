import SwiftUI

/// A single work-entry row: description as the headline, date/time as secondary
/// info, and duration as a compact trailing badge. Supports an optional
/// selection-mode checkmark for the entries list's multi-select flow.
struct EntryRowView: View {
    let entry: WorkEntry
    var showsProjectContext: Bool = false
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.taskDescription.isEmpty ? "Untitled task" : entry.taskDescription)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if showsProjectContext, let project = entry.project {
                    Text("\(project.job?.name ?? "—") · \(project.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Label(DateDurationService.dateFormatter.string(from: entry.date), systemImage: "calendar")
                    Label(
                        "\(DateDurationService.timeFormatter.string(from: entry.startTime))–\(DateDurationService.timeFormatter.string(from: entry.endTime))",
                        systemImage: "clock"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(DateDurationService.formattedDuration(hours: entry.durationHours))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: selectionMode)
    }
}

#Preview {
    List {
        EntryRowView(entry: PreviewSupport.sampleProject.entries.first!, showsProjectContext: true)
        EntryRowView(entry: PreviewSupport.sampleProject.entries.first!, isSelected: true, selectionMode: true)
    }
    .modelContainer(PreviewSupport.container)
}
