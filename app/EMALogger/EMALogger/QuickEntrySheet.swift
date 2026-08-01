import SwiftUI

/// 从通知点进来后看到的唯一一屏：三个数、一个开关、一个按钮，记完即走。
/// 设计原则：采集工具的每一次点击都是依从率的税，这一屏的目标是把税降到最低。
struct QuickEntrySheet: View {
    let store: StudyStore
    @Environment(\.dismiss) private var dismiss

    @State private var mood: Double = 50
    @State private var agency: Double = 50
    @State private var metacognition: Double = 50
    @State private var melatoninTaken = false
    @State private var didPrefill = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 28) {
                    QuickRating(title: "How's your mood", value: $mood)
                    QuickRating(title: "Getting things done", value: $agency)
                    QuickRating(title: "Thinking clearly", value: $metacognition)

                    melatoninRow
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            submitButton
        }
        .background(.regularMaterial)
        .presentationDetents([.large])
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(28)
        .onAppear(perform: prefillFromSchedule)
    }

    // MARK: 各部分

    private var header: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(headline)
                .font(.headline)
                .padding(.top, 10)

            if let sub = subhead {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private var melatoninRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $melatoninTaken) {
                Text("Took melatonin last night")
                    .font(.callout)
            }
            if let expected = store.lastNightCondition {
                HStack(spacing: 4) {
                    Image(systemName: (expected == 1) == melatoninTaken
                          ? "checkmark.circle" : "exclamationmark.triangle")
                    Text((expected == 1) == melatoninTaken
                         ? "Matches the schedule"
                         : "Schedule said \(expected == 1 ? "take it" : "skip it") · recorded as an override")
                }
                .font(.caption2)
                .foregroundStyle((expected == 1) == melatoninTaken ? Color.secondary : Color.orange)
            }
        }
        .padding(.top, 4)
    }

    private var submitButton: some View {
        Button {
            store.add(mood: mood, agency: agency,
                      metacognition: metacognition, melatonin: melatoninTaken)
            dismiss()
        } label: {
            Text("Log")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    // MARK: 文案

    private var headline: String {
        switch store.checkInState {
        case .windowOpen(let slot, let total, _):
            return "Check-in \(slot) of \(total)"
        case .windowClosed:
            return "Off-window entry"
        case .beforeStudy:
            return "Before the study starts"
        case .afterStudy:
            return "After the study"
        }
    }

    private var subhead: String? {
        switch store.checkInState {
        case .windowOpen(_, _, let closesAt):
            return "Day \(store.currentStudyDay) · closes \(closesAt.formatted(date: .omitted, time: .shortened))"
        case .windowClosed:
            return "Saved, but not counted toward compliance"
        default:
            return nil
        }
    }

    /// 昨晚的开关按方案预填，这样多数情况下受试者一下都不用碰它。
    /// 预填的是"方案说什么"，不是"你做了什么"，界面上明确写出来了。
    private func prefillFromSchedule() {
        guard !didPrefill else { return }
        didPrefill = true
        if let expected = store.lastNightCondition {
            melatoninTaken = (expected == 1)
        }
    }
}

/// 一行评分：大数字 + 滑块。数字大到余光可读，滑动时不用盯着看。
struct QuickRating: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: Int(value))
            }
            Slider(value: $value, in: 0...100, step: 1)
        }
    }
}
