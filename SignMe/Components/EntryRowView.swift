import SwiftUI

/// A single work-entry row: a date badge, the description, the time range
/// (with "+1" for overnight shifts and the break), and the worked duration in gold.
/// Supports a selection-mode checkmark for the entries list's multi-select flow.
struct EntryRowView: View {
    let entry: WorkEntry
    var showsProjectContext: Bool = false
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.app(.title3))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.textTertiary)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.appSize(11, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Theme.textSecondary)
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.appSize(17, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 42, height: 42)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.taskDescription.isEmpty ? "Untitled task" : entry.taskDescription)
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                if showsProjectContext, let project = entry.project {
                    Text("\(project.job?.name ?? "—") · \(project.name)")
                        .font(.app(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Text(timeRangeText)
                    .font(.app(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(DateDurationService.formattedDuration(hours: entry.durationHours))
                .font(.app(.subheadline, .bold))
                .foregroundStyle(Theme.gold)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: selectionMode)
        .accessibilityElement(children: .combine)
    }

    /// "09:00–17:00", plus "(+1)" for shifts past midnight and the break if any.
    private var timeRangeText: String {
        var text = "\(DateDurationService.timeFormatter.string(from: entry.startTime))–\(DateDurationService.timeFormatter.string(from: entry.endTime))"
        if DateDurationService.spansMidnight(start: entry.startTime, end: entry.endTime) {
            text += " (+1)"
        }
        if entry.breakMinutes > 0 {
            text += " · \(DateDurationService.formattedDuration(hours: Double(entry.breakMinutes) / 60)) break"
        }
        return text
    }
}

#Preview {
    VStack {
        EntryRowView(entry: PreviewSupport.sampleProject.entries.first!, showsProjectContext: true)
        EntryRowView(entry: PreviewSupport.sampleProject.entries.first!, isSelected: true, selectionMode: true)
    }
    .padding()
    .background(Theme.background)
    .modelContainer(PreviewSupport.container)
}
