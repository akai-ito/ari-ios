import AriKit
import SwiftUI

/// What Kumo learnt about you lately, in its own words to you, newest first, each with when.
/// Nothing to tap: to put one right, you tell Kumo.
struct LearntLately: View {
    let lines: [LearntLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What \(LeadName.current) learnt lately").font(.ariHeading).foregroundStyle(
                .ariText)
            if lines.isEmpty {
                Text(
                    "When \(LeadName.current) learns something about you, it says so here, in a line."
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text)
                                .font(.ariBody)
                                .foregroundStyle(.ariText)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ChapterReading.learnt(line.at))
                                .font(.caption)
                                .foregroundStyle(.ariTertiary)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        if line.id != lines.last?.id {
                            Rectangle().fill(Color.ariLine).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
                Text("Something not quite right? Tell \(LeadName.current) in chat.")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .padding(.leading, 4)
            }
        }
    }
}
