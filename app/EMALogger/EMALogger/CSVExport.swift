import Foundation

// CSV 导出。目标是让这份文件在 R 里 read.csv() 之后不需要任何清洗就能进分析：
// 时间用 ISO 8601，缺失用 NA，逻辑值用 0/1，自由文本按 RFC 4180 转义。

extension StudyStore {

    /// 一行表头 + 每条记录一行，按时间正序（分析习惯，与界面的倒序相反）
    var csvText: String {
        let header = [
            "timestamp", "study_day", "mood", "agency", "metacognition",
            "melatonin_taken", "scheduled_condition", "is_override",
            "override_reason", "source"
        ].joined(separator: ",")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        let rows = entries.sorted { $0.timestamp < $1.timestamp }.map { e -> String in
            [
                fmt.string(from: e.timestamp),
                String(e.studyDay),
                String(Int(e.mood)),
                String(Int(e.agency)),
                String(Int(e.metacognition)),
                e.melatoninTaken ? "1" : "0",
                e.scheduledCondition.map(String.init) ?? "NA",
                e.scheduledCondition == nil ? "NA" : (e.isOverride ? "1" : "0"),
                Self.csvQuote(e.overrideReason),
                e.source
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// RFC 4180：字段含逗号、引号或换行时整体加引号，内部引号翻倍。
    /// 缺失写 NA 而非空字符串，read.csv() 才会正确识别为 NA 而不是空串。
    private static func csvQuote(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "NA" }
        let escaped = v.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// 写进临时目录，交给分享面板。文件名带日期，导出多次不互相覆盖。
    func writeCSVFile() -> URL {
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ema_export_\(stamp).csv")
        try? csvText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 方案本身也值得导出：分析时要用它复原每天的指派
    func writeScheduleFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schedule.json")
        let ordered = config.schedule.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
        let body = ordered.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        try? "{\(body)}".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
