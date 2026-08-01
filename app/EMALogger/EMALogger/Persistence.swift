import Foundation

// MARK: - 数据模型

struct EMAEntry: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let studyDay: Int
    let mood: Double
    let agency: Double
    let metacognition: Double
    let melatoninTaken: Bool
    /// 记录当下方案对"昨晚"的指派，快照进数据，方案事后被改也不影响已收数据
    var scheduledCondition: Int? = nil
    /// 与方案不一致时的说明，对应原 Shortcut 的 override_reason
    var overrideReason: String? = nil
    /// 来源：app 界面还是 Shortcuts
    var source: String = "app"

    var isOverride: Bool {
        guard let s = scheduledCondition else { return false }
        return (s == 1) != melatoninTaken
    }
}

struct ReminderSlot: Codable, Identifiable, Hashable {
    var id = UUID()
    var hour: Int
    var minute: Int

    /// 今天的这个时刻，供 DatePicker 绑定用
    var todayAt: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}

struct StudyConfig: Codable {
    var startDate: Date = Calendar.current.startOfDay(for: .now)
    var durationDays: Int = 70
    var slots: [ReminderSlot] = [
        ReminderSlot(hour: 9,  minute: 0),
        ReminderSlot(hour: 15, minute: 0),
        ReminderSlot(hour: 21, minute: 0)
    ]
    var responseWindowHours: Int = 3
    var responseWindow: TimeInterval { TimeInterval(responseWindowHours) * 3600 }

    /// 预注册随机方案：研究日 -> 条件（0/1）。格式同 nof1kit::write_schedule() 的输出
    var schedule: [String: Int] = [:]

    func condition(forDay day: Int) -> Int? { schedule["\(day)"] }

    func studyDay(at date: Date = .now) -> Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: startDate)
        let to = cal.startOfDay(for: date)
        return (cal.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }
}

// MARK: - 持久化层
//
// 抽成独立的无状态层，因为 App Intent 会在 app 未运行时被 Shortcuts 调起，
// 那时没有任何视图或 @Observable 实例存在，必须能直接读写文件。

enum DataFile {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var entriesURL: URL { documents.appendingPathComponent("entries.json") }
    static var configURL:  URL { documents.appendingPathComponent("config.json") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func loadEntries() -> [EMAEntry] {
        guard let data = try? Data(contentsOf: entriesURL),
              let list = try? decoder.decode([EMAEntry].self, from: data) else { return [] }
        return list
    }

    static func saveEntries(_ entries: [EMAEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }

    static func loadConfig() -> StudyConfig {
        guard let data = try? Data(contentsOf: configURL),
              let c = try? decoder.decode(StudyConfig.self, from: data) else { return StudyConfig() }
        return c
    }

    static func saveConfig(_ config: StudyConfig) {
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    /// 追加一条记录，供界面和 Intent 共用。返回写入后的完整列表。
    @discardableResult
    static func append(_ entry: EMAEntry) -> [EMAEntry] {
        var list = loadEntries()
        list.insert(entry, at: 0)
        saveEntries(list)
        return list
    }
}

// MARK: - 内置样例方案

enum SampleSchedule {
    /// 2026 年 2 月真实跑过的 70 天预注册序列，来自 melatonin-ema-logger 的 schedule.json
    static let meng2026: [String: Int] = [
        "1":0,"2":0,"3":1,"4":0,"5":1,"6":1,"7":0,"8":1,"9":0,"10":0,
        "11":1,"12":0,"13":1,"14":1,"15":0,"16":1,"17":1,"18":0,"19":0,"20":1,
        "21":0,"22":0,"23":1,"24":0,"25":1,"26":0,"27":1,"28":0,"29":0,"30":1,
        "31":1,"32":0,"33":1,"34":0,"35":1,"36":1,"37":0,"38":1,"39":1,"40":0,
        "41":1,"42":0,"43":1,"44":1,"45":0,"46":1,"47":0,"48":0,"49":1,"50":1,
        "51":0,"52":0,"53":1,"54":1,"55":0,"56":0,"57":1,"58":0,"59":1,"60":1,
        "61":0,"62":0,"63":1,"64":1,"65":0,"66":0,"67":1,"68":1,"69":0,"70":0
    ]
}
