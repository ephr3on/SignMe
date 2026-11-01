import SwiftUI

/// The card used to represent a Job in the Jobs list.
struct JobCardView: View {
    let job: Job

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "briefcase.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(job.projects.count) project\(job.projects.count == 1 ? "" : "s") · \(DateDurationService.formattedDuration(hours: job.totalHours))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let last = job.lastActivityDate {
                    Text("Last activity \(DateDurationService.relativeFormatter.localizedString(for: last, relativeTo: .now))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

#Preview {
    JobCardView(job: PreviewSupport.sampleJob)
        .padding()
        .modelContainer(PreviewSupport.container)
}
