import AppIntents

// Shortcuts 调用这里的 Intent 来读方案、写记录。
// 前端保留 Shortcuts 的零成本悬浮输入，后端换成这个 app：
// 方案查询、窗口判定、范围校验、结构化存储都由 app 负责。

// MARK: - 查询今晚的指派

struct TonightConditionIntent: AppIntent {
    static var title: LocalizedStringResource = "Get tonight's assignment"
    static var description = IntentDescription(
        "Returns the preregistered condition for tonight: 1 = take melatonin, 0 = do not.",
        categoryName: "Protocol")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let config = DataFile.loadConfig()
        let day = config.studyDay()

        guard day >= 1, day <= config.durationDays else {
            return .result(value: -1, dialog: "Outside the study period (day \(day)).")
        }
        guard let condition = config.condition(forDay: day) else {
            return .result(value: -1, dialog: "No assignment loaded for day \(day).")
        }
        let text = condition == 1 ? "take melatonin" : "no melatonin"
        return .result(value: condition, dialog: "Day \(day): \(text).")
    }
}

// MARK: - 查询当前研究日

struct StudyDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Get current study day"
    static var description = IntentDescription(
        "Returns which day of the study today is.", categoryName: "Protocol")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: DataFile.loadConfig().studyDay())
    }
}

// MARK: - 记录一条 EMA

struct LogEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a check-in"
    static var description = IntentDescription(
        "Records one EMA check-in with the three ratings and last night's melatonin.",
        categoryName: "Check-in")

    // 参数文案走日常语言，构念名留在 app 里。问得越像人话，答得越可信。
    @Parameter(title: "Mood right now (0–100)", inclusiveRange: (0, 100))
    var mood: Int

    @Parameter(title: "Getting things done (0–100)", inclusiveRange: (0, 100))
    var agency: Int

    @Parameter(title: "Thinking clearly (0–100)", inclusiveRange: (0, 100))
    var metacognition: Int

    @Parameter(title: "Took melatonin last night")
    var melatoninTaken: Bool

    @Parameter(title: "Reason, if it differed from the schedule")
    var overrideReason: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log mood \(\.$mood), agency \(\.$agency), clarity \(\.$metacognition)") {
            \.$melatoninTaken
            \.$overrideReason
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = DataFile.loadConfig()
        let day = config.studyDay()

        // 范围校验：Shortcuts 那头可以输入任何数字，这里是最后一道关
        let clamp = { (v: Int) in min(max(v, 0), 100) }

        let entry = EMAEntry(
            timestamp: .now,
            studyDay: day,
            mood: Double(clamp(mood)),
            agency: Double(clamp(agency)),
            metacognition: Double(clamp(metacognition)),
            melatoninTaken: melatoninTaken,
            scheduledCondition: config.condition(forDay: day - 1),
            overrideReason: overrideReason?.isEmpty == true ? nil : overrideReason,
            source: "shortcuts")

        DataFile.append(entry)

        let note = entry.isOverride ? " Recorded as an override." : ""
        return .result(dialog: "Logged for day \(day).\(note)")
    }
}

// MARK: - 让 Intent 出现在 Shortcuts 和 Siri 里

struct EMAShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogEntryIntent(),
            phrases: ["Log a check-in in \(.applicationName)",
                      "Record my mood in \(.applicationName)"],
            shortTitle: "Log check-in",
            systemImageName: "square.and.pencil")

        AppShortcut(
            intent: TonightConditionIntent(),
            phrases: ["What's tonight's assignment in \(.applicationName)",
                      "Check my protocol in \(.applicationName)"],
            shortTitle: "Tonight's assignment",
            systemImageName: "moon")
    }
}
