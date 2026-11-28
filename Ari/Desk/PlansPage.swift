import AriKit
import SwiftUI

/// All of Kumo's plans, with plain titles: one-offs under Today, Tomorrow, Later this week and
/// Later, each repeat once under Repeating, with tonight's time also under Today. A tap opens why
/// and what Kumo will do; a long press moves or cancels it.
struct PlansPage: View {
    let session: Session

    @State private var opened: WakeUp?
    @State private var editing: WakeUp?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let groups = PlanReading.group(session.desk?.plans ?? [], now: DeskClock.now())
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if (session.desk?.plans ?? []).isEmpty {
                    Text(
                        "Nothing planned. When I set myself a reminder to look at something, it shows here."
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                section("Today", groups.today)
                section("Tomorrow", groups.tomorrow)
                section("Later this week", groups.laterThisWeek, showsDay: true)
                section("Later", groups.later, showsDay: true)
                if !groups.repeating.isEmpty { repeating(groups.repeating) }
                Text("Long-press a plan to move or cancel it. Tell me to change anything else.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $opened) { plan in
            PlanDetail(plan: plan, session: session)
                .presentationDetents([.fraction(0.66), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ariBackground)
        }
        .sheet(item: $editing) { PlanEditor(plan: $0, session: session) }
        .task { try? await session.refreshPlans() }
        #if DEBUG
            .task {
                guard DebugScript.desk == "plan" else { return }
                try? await Task.sleep(for: .milliseconds(900))
                opened = groups.repeating.first
            }
        #endif
    }

    @ViewBuilder
    private func section(_ title: String, _ plans: [WakeUp], showsDay: Bool = false) -> some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DeskSectionLabel(title)
                ForEach(plans) { plan in
                    PlanLine(plan: plan, showsDay: showsDay) { opened = plan }
                        .contextMenu { menu(plan) }
                }
            }
        }
    }

    private func repeating(_ plans: [WakeUp]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel("Repeating")
            ForEach(plans) { plan in
                Button {
                    opened = plan
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariTertiary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(plan.shownTitle).foregroundStyle(.ariText)
                        if let repeating = plan.repeat {
                            Text("·").foregroundStyle(.ariTertiary)
                            Text("\(PlanWords.repeats(repeating)) \(repeating.time)")
                                .foregroundStyle(.ariSecondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { menu(plan) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func menu(_ plan: WakeUp) -> some View {
        Button("Change…", systemImage: "pencil") { editing = plan }
        Button("Cancel this plan", systemImage: "xmark", role: .destructive) {
            Task { try? await session.cancel(plan.id) }
        }
    }
}
